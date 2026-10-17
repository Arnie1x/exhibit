"""Stage 2 acceptance: every tool must answer, with the numbers `make smoke` prints.

Exit code 0 means the tool layer and the database agree. Any mismatch is a real bug -- either the
tool is wrong or the corpus moved, and both need to be known before a demo.
"""
from __future__ import annotations

import sys
from typing import Any

import psycopg

from . import db, tools
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
    print(f"exhibit stage-2 acceptance | datasets: {catalogue()}")
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
    check("engineer reads raw lines", eng["rows"][0]["readable_as"], "bgl_ev")
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

    failures = [r for r in _results if r[0] == FAIL]
    print(f"\n{len(_results) - len(failures)}/{len(_results)} checks passed")
    if failures:
        print("FAILED:", ", ".join(f[1] for f in failures))
        return 1
    print("Stage 2 acceptance: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
