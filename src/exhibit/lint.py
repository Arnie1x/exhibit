"""The answer lints — what a persona's answer may and may not claim.

Both rules are promised in the plan (`docs/build-plan.md` §6) and enforced here, in code, because
both are the kind of thing that is easy to promise and easy to forget the moment a demo is running:

* the **manager lint**: a manager answer may not mention money, downtime, customers, revenue or an
  SLA. This corpus has no such columns — the words would be an invention, and an invented number is
  precisely the failure mode this project exists to catch. A term inside backticks or double quotes
  is allowed: the rule bans *claiming*, not *quoting*.
* the **numeric lint**: every bullet in the *Observed* block that contains a figure cites an
  evidence id, every cited id resolves in the ledger, and with ``deep=True`` the figures are looked
  for in the rows that statement returns. An answer whose numbers are not in the tool output is
  rejected.

A lint never rewrites the answer. A lint that edits is a lint nobody can check — it returns
findings, and the caller decides. It is also deliberately *not* recorded in the evidence ledger and
carries no ``E-`` id: the ledger holds re-runnable statements, and a lint is an opinion about prose,
not a data claim.
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

from . import ledger

BANNED = (
    ("€", re.compile("€")),
    ("$", re.compile(r"\$")),
    ("downtime", re.compile(r"\bdowntime\b", re.I)),
    ("customers", re.compile(r"\bcustomers?\b", re.I)),
    ("revenue", re.compile(r"\brevenue\b", re.I)),
    ("SLA", re.compile(r"\bSLAs?\b", re.I)),
)

# The contract's section names, with the parenthetical the contract shows after two of them.
SECTIONS = (
    "scope",
    "answer",
    "observed",
    "likely explanation",
    "not established",
    "recommended next steps",
    "evidence",
)
# Two shapes, both from the contract: `Scope: <inline body>` and a heading alone on its line
# (`Observed (measured)`). A line that merely starts with the word -- "Answering the question" --
# is prose, not a header, which is why the colon (or end of line) is required.
_HEADER = re.compile(
    r"^[*#>\s]{0,4}(" + "|".join(s.replace(" ", r"\s+") for s in SECTIONS) + r")\b"
    r"(\s*\([^)\n]*\))?\s*(?:\s*:\s*[^\n]*|)$",
    re.I | re.M,
)
_EID = re.compile(r"\bE-[0-9A-F]{6}\b", re.I)
_NUMBER = re.compile(r"\d[\d,_.]*(?:\s*%|%)?")
_QUOTED = re.compile(r"`[^`]*`|\"[^\"]*\"|'[^']*'")
_CAUSAL = re.compile(
    r"\b(co-?occur\w*|correlat\w*|because|due to|caused?|root cause)\b", re.I
)
_RELATIVE = re.compile(
    r"\b(last|past|previous|recent)\s+\d+\s*(day|week|month|year|hour)s?\b", re.I
)
_FREQUENCY = re.compile(r"\b[\d,]+ (?:log )?lines?\b", re.I)
# A hyphenated compound ("5-minute gap", "60-minute window") qualifies a noun: it is a method
# statement, not a count of anything, so it is not a data figure. A standalone figure is -- which
# is why "124 days" still has to resolve.
_HYPHEN_TAIL = re.compile(r"\s*[-–]\s*[A-Za-z]")
_EPISODES = re.compile(r"\bepisodes?\b", re.I)


def _finding(severity: str, rule: str, section: str, message: str) -> dict[str, str]:
    return {"severity": severity, "rule": rule, "section": section, "message": message}


def _split_sections(answer: str) -> dict[str, str]:
    """Map section name -> body. Prose before the first header lands under ``_preamble``."""
    marks = [(m.start(), m.end(), m.group(1).lower()) for m in _HEADER.finditer(answer)]
    out: dict[str, str] = {}
    if not marks:
        return {"_preamble": answer}
    if marks[0][0] > 0:
        out["_preamble"] = answer[: marks[0][0]]
    for i, (_s, end, name) in enumerate(marks):
        stop = marks[i + 1][0] if i + 1 < len(marks) else len(answer)
        name = re.sub(r"\s+", " ", name)
        out[name] = answer[end:stop]
    return out


def _bullets(body: str) -> list[str]:
    """Bullet lines, with wrapped continuation lines folded back in."""
    items: list[str] = []
    for line in body.splitlines():
        if re.match(r"^\s*[-*•]\s+", line):
            items.append(re.sub(r"^\s*[-*•]\s+", "", line).strip())
        elif items and line.strip() and not _HEADER.match(line):
            items[-1] += " " + line.strip()
    return [i for i in items if i]


def _number_forms(raw: str) -> set[str]:
    """The plausible spellings of one figure, so 152,182 / 152182 / 99.64 / 99.6 all resolve."""
    token = raw.strip().rstrip(",").strip()
    forms = {token, token.replace(",", ""), token.replace(" ", "").replace(",", "")}
    bare = token.replace(",", "").rstrip("%").strip()
    try:
        value = float(bare)
    except ValueError:
        return forms
    forms |= {str(int(value)) if value.is_integer() else str(value), f"{value:,.0f}"}
    for places in (1, 2):
        forms.add(f"{value:.{places}f}")
        forms.add(f"{value:,.{places}f}")
    return forms


def _strip_quoted(text: str) -> str:
    return _QUOTED.sub(" ", text)


def lint_answer(answer: str, persona: str = "", deep: bool = False) -> dict[str, Any]:
    """Check an answer against the two lints and the answer contract.

    ``deep=True`` re-runs each cited statement and looks for the figure in the rows it returns.
    That costs one query per cited id, so it is opt-in and is what `make check` exercises.
    """
    answer = answer or ""
    who = (persona or "").strip().lower()
    sections = _split_sections(answer)
    findings: list[dict[str, str]] = []

    # -- the manager lint ------------------------------------------------------------------
    if who == "manager":
        scanned = _strip_quoted(answer)
        for label, pattern in BANNED:
            for match in pattern.finditer(scanned):
                findings.append(
                    _finding(
                        "reject",
                        "manager-vocabulary",
                        _section_of(answer, match.start()),
                        f"the manager answer says {label!r}, and this corpus has no column that "
                        f"measures it ({label!r} is quotable inside backticks or quotes, but it "
                        f"cannot be claimed)",
                    )
                )
    elif who:
        scanned = _strip_quoted(answer)
        for label, pattern in BANNED:
            if label in ("€", "$") and pattern.search(scanned):
                findings.append(
                    _finding(
                        "info",
                        "manager-vocabulary",
                        "answer",
                        f"{label!r} would be rejected outright in a manager answer; this one is "
                        f"for {who!r}, so it is only flagged",
                    )
                )

    # -- the numeric lint ------------------------------------------------------------------
    observed = sections.get("observed", "")
    cited_all: list[str] = []
    if not observed:
        findings.append(
            _finding(
                "warn",
                "contract-shape",
                "observed",
                "no Observed block: measured facts must sit in their own block, because that is "
                "the block the contract separates from hypothesis",
            )
        )
    for bullet in _bullets(observed):
        ids = {m.group(0).upper() for m in _EID.finditer(bullet)}
        cited_all.extend(sorted(ids))
        masked = _EID.sub(lambda m: " " * len(m.group(0)), bullet)
        numbers = [
            m.group(0)
            for m in _NUMBER.finditer(masked)
            if m.group(0).strip(" ,.") and not _HYPHEN_TAIL.match(masked[m.end():])
        ]
        if numbers and not ids:
            findings.append(
                _finding(
                    "reject",
                    "number-without-evidence",
                    "observed",
                    f"a figure with no evidence id: {bullet[:110]!r} — re-run the statement and "
                    f"cite it, or the number is not checkable",
                )
            )
        elif numbers and ids and deep:
            known = {i: ledger.latest(i) for i in sorted(ids)}
            for i, entry in known.items():
                if entry is None:
                    findings.append(
                        _finding(
                            "reject",
                            "unknown-evidence",
                            "observed",
                            f"{i} is not in the ledger ({bullet[:70]!r}); every cited id must "
                            f"resolve, or the answer cites something that was never run",
                        )
                    )
            for i, entry in known.items():
                if entry is None:
                    continue
                # A figure that is one of the statement's own parameters ("5-minute gap") is an
                # echo of the request, not a data claim -- but a figure bigger than the sample
                # excuses nothing: every remaining figure must be findable, one by one.
                params_text = " | ".join(
                    str(p) for p in json.loads(entry["params_json"] or "[]")
                )
                echoed = set(re.findall(r"[\d][\d,\.]*", params_text))
                figures = [n for n in numbers if not (_number_forms(n) & echoed)]
                if not figures:
                    continue
                try:
                    checked = ledger.verify(i, sample=200)
                except Exception:                    # noqa: BLE001 - a lint must not raise
                    continue
                # A figure is evidenced if it is a value in the rows, the number of rows the
                # statement returns, or an aggregate (sum / min / max) of one of its columns:
                # "348,460 alert lines in total" is a total, and a total the statement does not
                # produce is exactly what this lint is for.
                supported = " | ".join(
                    str(v) for row in checked["rows_now_sample"] for v in row.values()
                ) + " | " + " | ".join(
                    str(v) for v in (checked.get("aggregates_now") or {}).values()
                )
                if checked.get("total_recorded") is not None:
                    supported += f" | {checked['total_recorded']}"
                haystack = set(re.findall(r"[\d][\d,\.]*", supported))
                missing = [n for n in figures if not (_number_forms(n) & haystack)]
                if missing:
                    findings.append(
                        _finding(
                            "warn",
                            "figure-not-in-evidence",
                            "observed",
                            f"{', '.join(missing[:4])} appear in no row of the first 200 that "
                            f"{i} returns (the result may be larger than the sample, or the figure "
                            f"is wrong; a figure derived from others should cite its components)",
                        )
                    )

    # -- the contract's own rules ----------------------------------------------------------
    for name in ("scope", "answer", "observed", "evidence"):
        if name not in sections:
            findings.append(
                _finding("warn", "contract-shape", name, f"the answer has no {name!r} block")
            )

    prose = _strip_quoted(sections.get("answer", "") + "\n" + observed)
    if _CAUSAL.search(prose):
        findings.append(
            _finding(
                "warn",
                "cause-vs-coincidence",
                "observed",
                "causal or co-occurrence language sits outside the hypothesis block; "
                "co-occurrence is not a cause, and the contract puts it under "
                "'Likely explanation'",
            )
        )

    for match in _RELATIVE.finditer(prose):
        findings.append(
            _finding(
                "info",
                "relative-period",
                "observed",
                f"{match.group(0)!r} must anchor to the dataset's last timestamp, not today "
                f"(BGL ends 2006-01-04, OpenStack 2017-05-17); the scope line resolves it",
            )
        )
        break

    if _FREQUENCY.search(observed) and not _EPISODES.search(observed):
        findings.append(
            _finding(
                "info",
                "lines-vs-episodes",
                "observed",
                "a line count with no episode count beside it; where episodes were computed the "
                "contract reads 'N log lines (M episodes at a 5-minute gap)'",
            )
        )

    counts = {
        "reject": sum(1 for f in findings if f["severity"] == "reject"),
        "warn": sum(1 for f in findings if f["severity"] == "warn"),
        "info": sum(1 for f in findings if f["severity"] == "info"),
    }
    verdict = "rejected" if counts["reject"] else ("warnings" if counts["warn"] else "ok")
    digest = hashlib.sha1(answer.strip().encode()).hexdigest()[:10].upper()

    rows = findings or [
        _finding("ok", "all", "-", "no findings: the answer passes both lints and the contract")
    ]
    notes = [
        "a lint is an opinion about prose, not a data claim: it is deliberately not recorded in "
        "the evidence ledger and carries no E- id",
    ]
    if not deep:
        notes.append(
            "shallow pass: the figures were not compared against the rows the cited statements "
            "return (call again with deep=True for that, at one query per cited id)"
        )
    else:
        notes.append(
            "deep pass: each cited statement was re-run and its first 200 rows searched for the "
            "figures"
        )

    return {
        "tool": "lint_answer",
        "dataset": None,
        "persona": who or "(any)",
        "role": "(none — no statement was run)",
        "refused": False,
        "measure": None,
        "scope": {"persona": who or None, "deep": deep, "characters": len(answer)},
        "answer_digest": f"L-{digest}",
        "verdict": verdict,
        "counts": counts,
        "total_matches": len(findings),
        "returned": len(rows),
        "truncated": False,
        "operator": "",
        "columns": ["severity", "rule", "section", "message"],
        "rows": rows,
        "query": "-- lint_answer runs no statement",
        "notes": notes,
        "cited": sorted(set(cited_all)),
    }


def _section_of(answer: str, offset: int) -> str:
    """Which block an offset falls in: the last section header at or before it."""
    current = "answer"
    for match in _HEADER.finditer(answer):
        if match.start() > offset:
            break
        current = re.sub(r"\s+", " ", match.group(1).lower())
    return current
