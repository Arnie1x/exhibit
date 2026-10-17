"""Acceptance: every tool must answer, with the numbers `make smoke` prints.

Exit code 0 means the tool layer, the analysis layer and the database agree. Any mismatch is a real
bug -- either the tool is wrong or the corpus moved, and both need to be known before a demo.

Stage 3's checks are written the same way: not "does `episodes` return a number" but "does it return
19,250 at a five-minute gap, 14,479 at an hour, and does its five-minute count equal the value of
the prebuilt view it recomputes". A check that cannot fail on a wrong number is decoration.
"""
from __future__ import annotations

import sys
from typing import Any

import psycopg

from . import analytics, db, ledger, lint, tools
from .datasets import catalogue

PASS, FAIL = "PASS", "FAIL"
_results: list[tuple[str, str, Any, Any]] = []


def check(label: str, actual: Any, expected: Any) -> None:
    ok = actual == expected
    _results.append((PASS if ok else FAIL, label, actual, expected))
    mark = "\u2713" if ok else "\u2717"
    shown = "" if ok else f"   expected {expected!r}, got {actual!r}"
    print(f"  {mark} {label}{shown}")


def main() -> int:
    print(f"exhibit acceptance | datasets: {catalogue()}")
    print(f"  engine: {db.ping()}")

    print("\nregression vs make smoke")
    check("bgl rows (as the engineer role)", tools.describe_data(dataset="bgl")["rows"][0]["total"], 4_747_963)
    check("openstack rows", tools.describe_data(dataset="openstack")["rows"][0]["total"], 207_812)
    check("bgl alert lines", db.scalar("SELECT count(*) FROM bgl_ev WHERE is_alert"), 348_460)
    check(
        "episodes at a 5-minute gap (signature x midplane)",
        db.scalar("SELECT count(*) FROM (SELECT DISTINCT signature, midplane, episode_no FROM bgl_episode) e"),
        19_250,
    )
    # The one-node burst: measured over the WHOLE day. The 136,209 we published first was this
    # burst cut at a 23:00 window boundary -- the trap is kept as a check so it cannot come back.
    check(
        "the one-node burst (whole day, not a window cut at 23:00)",
        db.scalar("SELECT count(*) FROM bgl_ev WHERE is_alert "
                  "AND ts >= TIMESTAMP '2005-06-11' AND ts < TIMESTAMP '2005-06-12'"),
        152_183,
    )
    check(
        "the burst is ONE node over 6h21m48s",
        db.scalar("SELECT count(DISTINCT node) FROM bgl_ev WHERE is_alert "
                  "AND ts >= TIMESTAMP '2005-06-11' AND ts < TIMESTAMP '2005-06-12'"),
        1,
    )
    check(
        "the trap reproduces: a 23:00 cut gives 136,209 (the wrong figure, guarded)",
        db.scalar("SELECT count(*) FROM bgl_ev WHERE is_alert "
                  "AND ts >= TIMESTAMP '2005-06-11 17:00:00' AND ts < TIMESTAMP '2005-06-11 23:00:00'"),
        136_209,
    )
    check(
        "the fleet event's lines",
        db.scalar("SELECT count(*) FROM bgl_ev WHERE is_alert "
                  "AND ts >= TIMESTAMP '2005-06-14' AND ts < TIMESTAMP '2005-06-15'"),
        49_154,
    )
    check(
        "the fleet event's blast radius",
        db.scalar("SELECT count(DISTINCT node) FROM bgl_ev WHERE is_alert "
                  "AND ts >= TIMESTAMP '2005-06-14' AND ts < TIMESTAMP '2005-06-15'"),
        22_529,
    )

    print("\nsearch_logs -- one check per operator, because they are not comparable")
    phrase = tools.search_logs("bgl", "data TLB error interrupt", mode="phrase", limit=2)
    check("phrase: 'data TLB error interrupt'", phrase["total_matches"], 152_734)
    check("phrase result is truncated", phrase["truncated"], True)
    check("phrase operator is reported", phrase["operator"], "phrase (ts_phrase)")
    check("highlight present", "<b>" in (phrase["rows"][0].get("highlight") or ""), True)

    term = tools.search_logs("bgl", "ciod", mode="term", limit=1)
    check("term: 'ciod'", term["total_matches"], 350_567)

    anyof = tools.search_logs("bgl", "ciod,Lustre", mode="any", limit=1)
    check("any-of: ['ciod','Lustre']", anyof["total_matches"], 382_098)

    os_phrase = tools.search_logs("openstack", "Unknown base file", mode="phrase", limit=1)
    check("openstack phrase: 'Unknown base file'", os_phrase["total_matches"], 3_059)

    print("\ncount_events -- aggregation on the table")
    teams = tools.count_events("bgl", group_by="team")
    by_team = {r["bucket"]: r["n"] for r in teams["rows"]}
    check("bgl by team: compute-platform", by_team.get("compute-platform"), 4_325_112)
    check("bgl by team: total", teams["total_matches"], 4_747_963)
    levels = tools.count_events("openstack", group_by="level")
    by_level = {r["bucket"]: r["n"] for r in levels["rows"]}
    check("openstack by level: ERROR", by_level.get("ERROR"), 186)
    check("openstack by level: CRITICAL", by_level.get("CRITICAL"), 2)
    check("openstack by level: WARNING", by_level.get("WARNING"), 3_118)

    counted = tools.count_events("bgl", group_by="component", query="ciod", mode="term")
    check("count_events with a search predicate", counted["total_matches"], 350_567)

    print("\nenvelope discipline")
    again = tools.search_logs("bgl", "data TLB error interrupt", mode="phrase", limit=2)
    other = tools.search_logs("bgl", "ciod", mode="term", limit=2)
    check("same query -> same evidence id", again["evidence_id"], phrase["evidence_id"])
    check("different query -> different id", other["evidence_id"] != phrase["evidence_id"], True)
    check("evidence carries the SQL", phrase["query"].startswith("SELECT"), True)
    check("evidence carries the operator", "operator" in phrase, True)
    check("truncated == total > returned", phrase["truncated"] == (phrase["total_matches"] > phrase["returned"]), True)

    print("\npersonas: three roles, three different views of the same data")
    eng = tools.describe_data(persona="engineer", dataset="bgl")
    check("engineer reads raw lines, with signatures on them",
          eng["rows"][0]["readable_as"], "bgl_sig")
    check("engineer can search", eng["rows"][0]["can_search"], True)
    lead = tools.describe_data(persona="lead", dataset="bgl")
    check("lead reads an aggregate, not lines", lead["rows"][0]["readable_as"], "lead_bgl_daily")
    check("lead cannot search", lead["rows"][0]["can_search"], False)
    check("manager reads only the rollup",
          tools.describe_data(persona="manager", dataset="corpus")["rows"][0]["readable_as"],
          "mgr_rollup_daily")

    lead_search = tools.search_logs("bgl", "ciod", persona="lead")
    check("the lead's search is refused, not silently empty", lead_search["refused"], True)
    check("the refusal names the persona", lead_search["persona"], "lead")
    check("the manager's search is refused too",
          tools.search_logs("bgl", "ciod", persona="manager")["refused"], True)
    check("the engineer's search is not refused",
          tools.search_logs("bgl", "ciod", persona="engineer", mode="term")["refused"], False)
    hidden = tools.count_events("corpus", persona="engineer")
    check("a persona cannot reach a dataset it has no view for", hidden["refused"], True)
    check("...and the refusal names what it may read",
          "cannot read 'corpus'" in hidden["notes"][0], True)

    lead_team = tools.count_events("bgl", group_by="team", persona="lead")
    check("lead counts by summing the view's measure", lead_team["measure"], "lines")
    check("lead total is still 4,747,963 lines", lead_team["total_matches"], 4_747_963)
    check("lead by team: compute-platform",
          {r["bucket"]: r["n"] for r in lead_team["rows"]}.get("compute-platform"), 4_325_112)

    mgr = tools.count_events("bgl", group_by="team", persona="manager")
    check("manager sums alert_lines, not rows", mgr["measure"], "alert_lines")
    check("manager total = 348,460 alert lines", mgr["total_matches"], 348_460)
    check("the never-sum warning is carried",
          any("never sum" in n for n in mgr["notes"]), True)

    try:
        db.query("SELECT 1 FROM bgl_ev LIMIT 1", role="exhibit_manager")
        check("the DATABASE refuses a manager reading bgl_ev", "allowed", "permission denied")
    except psycopg.errors.InsufficientPrivilege:
        check("the DATABASE refuses a manager reading bgl_ev", "permission denied", "permission denied")

    print("\nclient-side deadline (the engine accepts statement_timeout and ignores it)")
    try:
        db.query("SELECT pg_sleep(3)", timeout=0.5)
        check("a query over its deadline is cancelled", "not cancelled", "QueryTimeout")
    except db.QueryTimeout:
        check("a query over its deadline is cancelled", "QueryTimeout", "QueryTimeout")

    print("\nStage 3: incidents, not lines")
    ep1 = analytics.episodes("bgl", "engineer", gap_minutes=1, limit=1)
    ep5 = analytics.episodes("bgl", "engineer", gap_minutes=5, limit=1)
    ep60 = analytics.episodes("bgl", "engineer", gap_minutes=60, limit=1)
    check("episodes at a 1-minute gap", ep1["total_matches"], 22_002)
    check("episodes at a 5-minute gap", ep5["total_matches"], 19_250)
    check("episodes at a 60-minute gap", ep60["total_matches"], 14_479)
    check(
        "the tool recomputes what the prebuilt 5-minute view says",
        ep5["total_matches"],
        db.scalar("SELECT count(*) FROM (SELECT DISTINCT signature, midplane, episode_no"
                  " FROM bgl_episode) e"),
    )
    deepest = ep5["rows"][0]
    check("the deepest incident is ONE node, 152,182 KERNDTLB lines",
          (deepest["signature"], deepest["lines"], deepest["nodes"]),
          ("data TLB error interrupt", 152_182, 1))
    # Both burst numbers are right and they are different cuts: 152,183 is every alert line on that
    # node that day (152,182 KERNDTLB + 1 KERNMC); 152,182 is the one incident. Guard both, so a
    # future reader cannot "fix" one to match the other.
    check("the day's total for that node is 152,183 (two categories)",
          db.scalar("SELECT count(*) FROM bgl_ev WHERE is_alert AND node = 'R30-M0-N9-C:J16-U01'"
                    " AND ts >= TIMESTAMP '2005-06-11' AND ts < TIMESTAMP '2005-06-12'"), 152_183)
    check("the incident itself is 152,182",
          db.scalar("SELECT count(*) FROM bgl_ev WHERE is_alert AND alert_category = 'KERNDTLB'"
                    " AND node = 'R30-M0-N9-C:J16-U01' AND ts >= TIMESTAMP '2005-06-11'"
                    " AND ts < TIMESTAMP '2005-06-12'"), 152_182)
    check("episodes ignoring the failure domain (signature only)",
          analytics.episodes("bgl", "engineer", coalesce_by="signature", limit=1)["total_matches"],
          1_377)

    lead_ep = analytics.episodes("bgl", "lead", limit=1)
    check("the lead sees the same collapse: 19,250", lead_ep["total_matches"], 19_250)
    check("the manager sees the same collapse: 19,250",
          analytics.episodes("bgl", "manager", limit=1)["total_matches"], 19_250)
    gap_refused = analytics.episodes("bgl", "lead", gap_minutes=60, limit=1)
    check("the lead cannot vary the gap", gap_refused["refused"], True)
    check("...and the refusal says why", "not a parameter" in gap_refused["notes"][0], True)

    print("\nsignatures are signatures, not labels (the trap, in two calls)")
    sig = tools.count_events("bgl", group_by="signature", limit=1)
    cat = tools.count_events("bgl", group_by="category", limit=1)
    check("the engineer's `signature` group returns a masked signature",
          sig["rows"][0]["bucket"], "generating core.{n}")
    check("...while `category` still exposes the label everyone else trusts",
          cat["rows"][0]["bucket"], "-")
    check("...and that label sits on 4.4M of 4.7M lines", cat["rows"][0]["n"], 4_399_503)
    for gap, expect in ((1, 132), (5, 117), (60, 57)):
        e = analytics.episodes("bgl", "engineer", gap_minutes=gap,
                               signature="data TLB error interrupt", limit=1)
        check(f"episodes reproduces the DTLB headline at a {gap}-minute gap "
              f"(the gap bound through the driver, not a literal)",
              e["total_matches"], expect)
    check("the lead's relation can still filter by signature text",
          analytics.episodes("bgl", "lead", signature="data TLB error interrupt",
                             limit=1).get("refused", False), False)
    check("the manager cannot filter by signature text, and is told why",
          analytics.episodes("bgl", "manager", signature="data TLB error interrupt")["refused"], True)

    print("\ntop_signatures: the three rankings disagree, which is the finding")
    by_lines = analytics.top_signatures("bgl", "engineer", by="lines", limit=3)
    by_nodes = analytics.top_signatures("bgl", "engineer", by="nodes", limit=3)
    by_eps = analytics.top_signatures("bgl", "engineer", by="episodes", limit=3)
    check("ranked by lines: the log flood",
          by_lines["rows"][0]["signature"], "data TLB error interrupt")
    check("ranked by blast radius: a different problem",
          by_nodes["rows"][0]["signature"], "Microloader Assertion")
    check("ranked by episodes: a third one",
          by_eps["rows"][0]["signature"], "Lustre mount FAILED : bglio{n} : point /p/gb{n}")
    check("three criteria, three different answers",
          len({by_lines["rows"][0]["signature"], by_nodes["rows"][0]["signature"],
               by_eps["rows"][0]["signature"]}), 3)
    check("the lead's worst OpenStack problem is the imagecache warning",
          analytics.top_signatures("openstack", "lead", by="lines", limit=1)["rows"][0]["problem"],
          "image cache: unknown base file")

    print("\nblast radius: a column that reads 0 for a measurable reason")
    os_ep = analytics.episodes("openstack", "engineer", limit=1)
    check("openstack problem lines carry no instance id, and the answer says so",
          any("unmeasurable in instances" in n for n in os_ep["notes"]), True)
    check("...and bgl, where every line has a node, is not given that note",
          any("unmeasurable in instances" in n for n in ep5["notes"]), False)
    os_nodes = analytics.top_signatures("openstack", "engineer", by="nodes", limit=1)
    check("ranking openstack by blast radius is refused, not ranked 0 against 0",
          os_nodes["refused"], True)
    check("...and the refusal says what the corpus does instead",
          "0 against 0" in os_nodes["notes"][0], True)
    check("the manager's openstack blast radius is named for what it counts",
          "requests_affected" in analytics.top_signatures(
              "openstack", "manager", by="episodes", limit=1)["columns"], True)

    print("\ndurations, ownership and the record of what we asked")
    dur = analytics.durations(persona="engineer", limit=4)
    check("the worst spawn is a labelled anomaly",
          dur["rows"][0]["instance_id"], "a445709b-6ad0-40ec-8860-bec60b6ca0c2")
    check("one row per instance in the corpus", dur["total_matches"], 2_069)
    check("bgl has no lifecycle to time", analytics.durations(dataset="bgl")["refused"], True)
    check("the manager ranks percentiles, not instances",
          analytics.durations(persona="manager", by="spawn_max_s", limit=2)["refused"], False)

    own = analytics.ownership(persona="engineer")
    check("the ownership table we built", own["total_matches"], 23)
    check("...and nothing in the corpus is unmapped",
          any("unowned" in n for n in own["notes"]), True)
    check("the manager has no grant on it", analytics.ownership(persona="manager")["refused"], True)

    ne = analytics.nearby_events("bgl", "engineer", id=4_740_000, minutes=10, limit=2)
    check("nearby_events walks a window of lines", ne["total_matches"] > 0, True)
    check("nearby_events is engineer-only",
          analytics.nearby_events("bgl", "lead", ts="2006-01-04 04:00:00")["refused"], True)

    wc = analytics.what_changed("bgl", "engineer", window_hours=6, baseline_hours=24, limit=3)
    check("what_changed is anchored to the data's last line, not today",
          str(wc["scope"].get("anchor"))[:10], "2006-01-04")
    check("what_changed reports rate_ratio and is_new",
          {"is_new", "rate_ratio"} <= set(wc["columns"]), True)
    tr = analytics.trend("bgl", "engineer", bucket="day", limit=5)
    check("trend ends at the corpus's last day", str(tr["rows"][-1]["bucket"])[:10], "2006-01-04")
    check("a daily view cannot produce an hourly trend",
          analytics.trend("bgl", "lead", bucket="hour")["refused"], True)

    check("every Stage 3 answer is written to the evidence ledger",
          analytics.ledger.latest(ep5["evidence_id"]) is not None, True)
    check("verify_evidence reproduces a stored answer",
          analytics.verify_evidence(ep5["evidence_id"])["match"], True)
    try:
        analytics.verify_evidence("E-NOPE00")
        check("an unknown evidence id errors instead of guessing", "no error", "KeyError")
    except KeyError:
        check("an unknown evidence id errors instead of guessing", "KeyError", "KeyError")
    check("a refusal is recorded as evidence too",
          analytics.ledger.latest(gap_refused["evidence_id"]) is not None, True)

    print("\nevery answer survives a strict JSON client")
    # The engine hands back DECIMAL for sum(...), date for a bucketed day, datetime for a timestamp
    # and timedelta for a duration -- none of which json.dumps accepts. The checks above compare
    # Python objects and the MCP layer's pydantic models absorb the rest, so this shipped broken
    # once: a manager's ranked list raised TypeError on a strict client while everything here was
    # green. One check, every persona, every tool shape that has leaked so far.
    import json as _json
    strict_calls = {
        "describe_data eng": lambda: tools.describe_data(persona="engineer", dataset="bgl"),
        "count_events eng": lambda: tools.count_events("bgl", group_by="signature", limit=2),
        "search_logs eng": lambda: tools.search_logs("bgl", "ciod", limit=2),
        "top_signatures mgr": lambda: analytics.top_signatures("bgl", "manager", by="nodes", limit=2),
        "top_signatures lead": lambda: analytics.top_signatures("bgl", "lead", by="lines", limit=2),
        "episodes eng": lambda: analytics.episodes("bgl", "engineer", limit=2),
        "episodes lead": lambda: analytics.episodes("bgl", "lead", limit=2),
        "trend lead": lambda: analytics.trend("bgl", "lead", bucket="day", limit=2),
        "durations mgr": lambda: analytics.durations(persona="manager", limit=2),
        "ownership eng": lambda: analytics.ownership(persona="engineer"),
        "nearby_events eng": lambda: analytics.nearby_events("bgl", "engineer", id=4_740_000,
                                                             limit=1),
        "what_changed eng": lambda: analytics.what_changed("bgl", "engineer", limit=1),
    }
    unserialisable = []
    for name, call in strict_calls.items():
        try:
            _json.dumps(call())
        except (TypeError, ValueError) as exc:
            unserialisable.append(f"{name}: {exc}")
    check(f"all {len(strict_calls)} sampled answers serialise for a strict client",
          unserialisable or "all serialisable", "all serialisable")

    # The answer lints: promised in the plan (docs/build-plan.md section 6) and, until now, only
    # prose. The manager vocabulary rule and the numeric rule are worth very little as prose and a
    # lot as a check, because both are the kind of rule an agent forgets while the demo runs.
    print("\nanswer lints: the manager vocabulary rule and the numeric rule")
    manager_money = (
        "Scope: both datasets, whole corpus\n"
        "Answer: the failing node will cost $4,000 a month in downtime.\n"
        "Observed (measured)\n- 3,394 nodes affected [E-0012AB]\n"
        "Evidence\n| ID | tool |\n| E-0012AB | top_signatures |\n"
    )
    check(
        "manager lint: claiming money and downtime is rejected",
        lint.lint_answer(manager_money, persona="manager")["verdict"],
        "rejected",
    )
    check(
        "manager lint: the same words quoted from the logs are allowed",
        lint.lint_answer(
            manager_money.replace("$4,000 a month in downtime", "`Time out on <SLA>`"),
            persona="manager",
        )["counts"]["reject"],
        0,
    )
    check(
        "numeric lint: a figure with no evidence id is rejected",
        lint.lint_answer(
            "Scope: bgl\nAnswer: one node dominates.\nObserved (measured)\n"
            "- 152,182 alert lines on one node\n",
            persona="engineer",
        )["counts"]["reject"],
        1,
    )
    _lint_env = analytics.top_signatures(dataset="bgl", persona="lead", by="lines", limit=1)
    _lint_top, _lint_id = _lint_env["rows"][0], _lint_env["evidence_id"]
    _lint_ok = (
        f"Scope: bgl, whole corpus\nAnswer: one signature dominates by volume.\n"
        f"Observed (measured)\n- {_lint_top['lines']:,} alert lines, one node carrying it "
        f"[{_lint_id}]\nEvidence\n| ID |\n| {_lint_id} |\n"
    )
    check(
        "numeric lint, deep: the real figure (with its comma) resolves in the cited rows",
        lint.lint_answer(_lint_ok, persona="lead", deep=True)["verdict"],
        "ok",
    )
    check(
        "numeric lint, deep: a figure that is in no row of the cited statement is flagged",
        lint.lint_answer(
            _lint_ok.replace(f"{_lint_top['lines']:,}", "999,999"), persona="lead", deep=True
        )["counts"]["warn"],
        1,
    )

    # A refusal is recorded like an answer, so its id must be verifiable like one. It used to
    # raise: "the last operation didn't produce records". An id a caller can cite but not check is
    # worse than no id, and a crash on a citation is the worst version of that.
    _refusal = analytics.durations(persona="manager", limit=1)
    _refusal_verify = ledger.verify(_refusal["evidence_id"])
    check(
        "verify_evidence on a refusal says so instead of raising",
        _refusal_verify["verdict"].split(" -")[0],
        "REFUSAL",
    )
    check(
        "and the three tools that predate the ledger record too",
        all(
            ledger.latest(env["evidence_id"]) is not None
            for env in (
                tools.describe_data(persona="engineer"),
                tools.search_logs("bgl", "ciod", persona="engineer", limit=1),
                tools.count_events("bgl", persona="engineer", limit=1),
            )
        ),
        True,
    )

    failures = [r for r in _results if r[0] == FAIL]
    print(f"\n{len(_results) - len(failures)}/{len(_results)} checks passed")
    if failures:
        print("FAILED:", ", ".join(f[1] for f in failures))
        return 1
    print("Stage 2+3 acceptance: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
