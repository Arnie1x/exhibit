#!/usr/bin/env python3
"""The eval: the brief's questions, scored against hand-written SQL.

What this scores — and what it deliberately does not:

* it scores the **tool surface**: each question's call goes through the real MCP server over stdio,
  the way a judging client would drive it, not through the Python functions;
* it scores the **figures**: every number a question must carry is compared against a statement in
  `evals/golden.sql`, written by hand against the derived relations, so a change to a tool's SQL
  cannot quietly move a number;
* it scores the **chain to a linted answer**: from the values that came back it builds the answer a
  role would send, cites the evidence id, and puts it through the answer lints — the figures must
  resolve in the evidence and the manager's vocabulary rule must hold;
* it scores the **refusals**: three questions must be refused, by the right role, with a reason
  that names the door.

It does **not** score a model's prose. Nothing here can tell whether an LLM wrote a good paragraph
this morning; what it can tell is whether every figure such a paragraph would cite is reproducible,
checkable and correctly scoped. That is the part that has to be true, and it is the part the plan
promised (`docs/build-plan.md` §6, Stage 5).

Run: `make eval` (or `uv run python evals/run_eval.py`).
"""
from __future__ import annotations

import asyncio
import json
import pathlib
import re
import sys

import psycopg
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

REPO = pathlib.Path(__file__).resolve().parent.parent
GOLDEN = REPO / "evals" / "golden.sql"
QUESTIONS = REPO / "evals" / "questions.json"

PASS, FAIL = "PASS", "FAIL"


def golden_values() -> dict[str, int]:
    """Run every named statement in golden.sql once, straight to the database."""
    text = GOLDEN.read_text()
    pairs = re.findall(r"-- name: (\S+)\n(.*?);", text, re.S)
    if not pairs:
        raise SystemExit(f"no named statements found in {GOLDEN}")
    out: dict[str, int] = {}
    with psycopg.connect("host=127.0.0.1 port=7890 user=postgres dbname=postgres") as conn:
        for name, sql in pairs:
            sql = "\n".join(line for line in sql.splitlines() if not line.strip().startswith("--"))
            row = conn.execute(sql).fetchone()
            out[name] = int(row[0]) if row else 0
    return out


def resolve(doc: dict, path: str):
    """Resolve `rows[0].lines` against a document; `call2.x` is handled by the caller."""
    current = doc
    for part in re.findall(r"[^.\[\]]+|\[\d+\]", path):
        if part.startswith("["):
            current = current[int(part[1:-1])]
        else:
            current = current[part] if isinstance(current, dict) else None
        if current is None:
            return None
    return current


def payload(result) -> dict:
    for item in getattr(result, "content", []) or []:
        text = getattr(item, "text", None)
        if text:
            return json.loads(text)
    if getattr(result, "structured_content", None):
        return result.structured_content
    raise SystemExit(f"no text content in result: {result!r}")


def format_answer(template: str, doc: dict, call2: dict | None) -> str:
    """Fill an answer template from the envelope: dotted paths, `{eid}`, and `:,` for grouping."""
    flat: dict = dict(doc)
    flat["eid"] = doc.get("evidence_id", "")
    if call2:
        flat["call2"] = call2

    def substitute(match: re.Match) -> str:
        key, spec = match.group(1), match.group(2) or ""
        value = resolve(flat, key) if ("." in key or "[" in key) else flat.get(key)
        if isinstance(value, int) and "," in spec:
            return f"{value:,}"
        return str(value)

    return re.sub(r"\{([A-Za-z0-9_.\[\]]+)(:[^}]*)?\}", substitute, template)


async def main() -> int:
    gold = golden_values()
    bank = json.loads(QUESTIONS.read_text())["questions"]
    results: list[tuple[str, str, list[str]]] = []   # (verdict, id, details)
    figures_checked = 0
    figures_wrong = 0
    refusals_checked = 0

    params = StdioServerParameters(command="uv", args=["run", "python", "-m", "exhibit.server"], cwd=str(REPO))
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            for question in bank:
                qid, details, ok = question["id"], [], True
                calls = [question["call"]] + ([question["call2"]] if "call2" in question else [])
                envelopes: dict[str, dict] = {}
                for index, call in enumerate(calls, start=1):
                    env = payload(await session.call_tool(call["tool"], call["args"]))
                    envelopes[f"call{index}" if index > 1 else "call"] = env

                for path, expected in question["expect"].items():
                    # "rows[0].lines" and "total_matches" both address the first envelope;
                    # "call2.total_matches" addresses the second call's.
                    if path.startswith("call2."):
                        doc_key, field = "call2", path[len("call2."):]
                    else:
                        doc_key, field = "call", path
                    doc = envelopes[doc_key]
                    if field == "refused" and expected is True:
                        refusals_checked += 1
                        actual = bool(doc.get("refused"))
                        figures_checked += 1
                        if actual is not True:
                            ok = figures_wrong = figures_wrong + 1
                            details.append(f"expected a refusal on {doc_key}, got an answer")
                        continue
                    if field == "notes_contain":
                        refusals_checked += 1
                        notes = " ".join(doc.get("notes") or [])
                        if expected not in notes:
                            ok = False
                            details.append(f"{doc_key}: the refusal does not name {expected!r}")
                        continue
                    if isinstance(expected, list) and expected and expected[0] == "golden":
                        want = gold[expected[1]]
                        source = f"golden:{expected[1]}"
                    else:
                        want = expected
                        source = "literal"
                    actual = resolve(doc, field)
                    figures_checked += 1
                    if actual != want:
                        ok = False
                        figures_wrong += 1
                        details.append(f"{path}: expected {want!r} ({source}), got {actual!r}")

                # the chain to a linted answer
                lint = question.get("lint")
                if lint is None and "answer" in question:
                    text = format_answer(question["answer"], envelopes["call"], envelopes.get("call2"))
                    cited = envelopes["call"].get("evidence_id", "")
                    answer = (
                        f"Scope: {envelopes['call'].get('dataset')}, {envelopes['call'].get('persona')}\n"
                        f"Answer: see the evidence below.\n{text}\nEvidence\n| ID |\n| {cited} |\n"
                    )
                    verdict = payload(await session.call_tool(
                        "lint_answer", {"answer": answer, "persona": question["role"], "deep": True}))["verdict"]
                    if verdict != "ok":
                        ok = False
                        details.append(f"the lint rejects the answer built from this call: {verdict}")
                if lint:
                    eid = envelopes["call"]["evidence_id"]
                    bad = payload(await session.call_tool(
                        "lint_answer", {"answer": lint["bad"].format(eid=eid), "persona": question["role"]}))["verdict"]
                    good = payload(await session.call_tool(
                        "lint_answer", {"answer": lint["good"].format(eid=eid), "persona": question["role"]}))["verdict"]
                    if bad != lint["bad_verdict"] or good != lint["good_verdict"]:
                        ok = False
                        details.append(f"lint verdicts {bad!r}/{good!r} != {lint['bad_verdict']!r}/{lint['good_verdict']!r}")

                results.append((PASS if ok else FAIL, qid, details))

    print(f"exhibit eval | {len(bank)} questions | golden statements: {len(gold)}")
    print(f"{'':4}{'id':5} {'role':10} question")
    by_id = {q["id"]: q for q in bank}
    for verdict, qid, details in results:
        mark = "\u2713" if verdict == PASS else "\u2717"
        print(f"  {mark} {qid:5} {by_id[qid]['role']:10} {by_id[qid]['question'][:78]}")
        for line in details:
            print(f"         {line}")

    passed = sum(1 for r in results if r[0] == PASS)
    print(f"\nscore: {passed}/{len(results)} questions")
    print(f"figures: {figures_checked - figures_wrong}/{figures_checked} reproduced "
          f"({figures_wrong} wrong) | refusals exercised: {refusals_checked}")
    if passed != len(results):
        print("FAILED:", ", ".join(r[1] for r in results if r[0] == FAIL))
        return 1
    print("eval: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
