#!/usr/bin/env python3
"""Ground-truth validation, run OUTSIDE the agent: what our analysis recovered, scored against labels.

Two answer keys ship with the corpora, and they are not the same kind of thing:

* ``anomaly_labels.txt`` (OpenStack) names the 4 VM instances with injected anomalies. It is never
  loaded into SereneDB, no MCP tool reads it, and this script is not an MCP tool -- so the agent
  cannot see it, call it, or be tuned against it. The question it answers: does the ranking the
  agent's own ``durations`` tool returns put the labelled instances on top?
* BGL's label column is part of the data (``alert_category`` / ``is_alert``): the brief supplies it,
  the engineer can group by it, and "alert line" is defined from it. So it is not hidden, and this
  script does not pretend it is. What it checks instead is the backbone of every BGL ranking: does a
  signature computed from the message text ALONE reproduce the expert's label? If it does, ranking
  by signature loses nothing the label knew -- and the same method works on logs that carry no
  labels. A severity filter, the obvious label-free alternative, is scored beside it.

Every figure is computed by SereneDB; Python only compares a handful of aggregated rows. Each
expectation below is a measured value pinned on 17 Oct (``docs/validation.md``); a FAIL means the
data or a view moved, and the exit code is 1.

Run:  make validate        (= uv run python scripts/validate_ground_truth.py [--labels PATH])
"""
from __future__ import annotations

import argparse
import asyncio
import math
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "src"))

from exhibit import analytics, db  # after the path insert, so a bare checkout works too

UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
DEFAULT_LABELS = REPO / "data" / "loghub" / "anomaly_labels.txt"

_results: list[tuple[bool, str]] = []


def expect(label: str, ok: bool, shown: str = "") -> None:
    _results.append((ok, label))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}{(' -- ' + shown) if shown else ''}")


def pct(num: float, den: float) -> str:
    return f"{100.0 * num / den:.4f}%" if den else "n/a"


def read_labels(path: pathlib.Path) -> list[str]:
    """The answer key, read from disk here and nowhere else."""
    if not path.exists():
        sys.exit(f"labels not found: {path} (make fetch unpacks it into data/loghub/)")
    return sorted(set(UUID.findall(path.read_text(encoding="utf-8").lower())))


# ------------------------------------------------------------------------------- out of reach
def out_of_reach() -> None:
    print("\n0. The answer key is out of the agent's reach")
    tools = [t.name for t in asyncio.run(_tool_names())]
    leaked = [t for t in tools if re.search(r"valid|label|truth|anomal", t)]
    expect(f"none of the {len(tools)} MCP tools validates or reads labels", not leaked,
           ", ".join(leaked) or ", ".join(tools))
    # Catalog names only: no table, view or column in the database is named after the key.
    # (BGL's label lives on as alert_category, by design -- see the module docstring.)
    rows = db.query(
        "SELECT table_name AS name FROM information_schema.tables "
        "WHERE lower(table_name) LIKE '%anomal%' OR lower(table_name) LIKE '%truth%' "
        "UNION ALL "
        "SELECT table_name || '.' || column_name FROM information_schema.columns "
        "WHERE lower(column_name) LIKE '%anomal%' OR lower(column_name) LIKE '%truth%'"
    )
    expect("no relation or column in SereneDB holds anomaly_labels.txt", not rows,
           ", ".join(r["name"] for r in rows) or "0 relations, 0 columns")


async def _tool_names():
    from exhibit.server import mcp  # the server's own registry, not a copy of it
    return await mcp.list_tools()


# ------------------------------------------------------------------------------- OpenStack
def openstack(labels: list[str]) -> None:
    print(f"\n1. OpenStack: {len(labels)} labelled instances (anomaly_labels.txt)")
    expect("the answer key names 4 instances", len(labels) == 4, ", ".join(x[:8] for x in labels))

    # What the agent sees: the lead's durations tool, worst spawn first. It records evidence, so
    # the ranking we score below can be re-run with verify_evidence.
    env = analytics.durations(dataset="openstack", persona="lead", by="spawn_s", limit=10)
    agent_top = [r["instance_id"] for r in env["rows"]]
    print(f"  agent path: [{env['evidence_id']}] durations(openstack, lead, by=spawn_s) -> "
          f"{env['total_matches']:,} instances, top {len(agent_top)} returned")

    # The full ranking, scored here as the connecting login (no role): every instance's position
    # by spawn, by image phase, and within its own file; ties break on instance_id.
    ranked = db.query(
        """
        WITH r AS (
            SELECT instance_id, source_file, spawn_s, image_s,
                   row_number() OVER (ORDER BY spawn_s DESC NULLS LAST, instance_id) AS pos_spawn,
                   row_number() OVER (ORDER BY image_s DESC NULLS LAST, instance_id) AS pos_image,
                   row_number() OVER (PARTITION BY source_file
                                      ORDER BY spawn_s DESC NULLS LAST, instance_id) AS pos_in_file,
                   count(*) OVER ()                         AS population,
                   count(*) OVER (PARTITION BY source_file) AS file_population
            FROM os_instance_durations
        )
        SELECT *, list_contains(%s::VARCHAR[], instance_id) AS labelled
        FROM r
        WHERE list_contains(%s::VARCHAR[], instance_id) OR pos_spawn <= 10
        ORDER BY pos_spawn
        """,
        [labels, labels],
    )
    population = ranked[0]["population"]
    print(f"  {'pos':>4} {'instance':<10} {'file':<24} {'spawn_s':>8} {'image_s':>8} "
          f"{'in file':>9}  labelled")
    for r in ranked:
        print(f"  {r['pos_spawn']:>4} {r['instance_id'][:8]:<10} {r['source_file']:<24} "
              f"{r['spawn_s'] if r['spawn_s'] is not None else '-':>8} "
              f"{r['image_s'] if r['image_s'] is not None else '-':>8} "
              f"{str(r['pos_in_file']) + '/' + str(r['file_population']):>9}  "
              f"{'YES' if r['labelled'] else ''}")

    hits = [r for r in ranked if r["labelled"]]
    sql_top = [r["instance_id"] for r in ranked if r["pos_spawn"] <= len(agent_top)]
    expect("the agent's ranking is the scored ranking (same top 10, same order)",
           agent_top == sql_top, f"{len(agent_top)} of {len(sql_top)} positions compared")

    for k in (4, 5, 10):
        found = sum(1 for r in hits if r["pos_spawn"] <= k)
        print(f"  recall@{k:<2} = {found}/{len(labels)}   precision@{k:<2} = {found}/{k}")
    positions = sorted(r["pos_spawn"] for r in hits)
    expect("all 4 labelled instances rank 1-4 of the whole fleet by spawn time",
           positions == [1, 2, 3, 4], f"positions {positions} of {population:,}")
    first_unlabelled = next(r for r in ranked if not r["labelled"])
    expect("position 5 is the first unlabelled instance (the near miss)",
           first_unlabelled["pos_spawn"] == 5,
           f"{first_unlabelled['instance_id'][:8]} in {first_unlabelled['source_file']}, "
           f"spawn {first_unlabelled['spawn_s']} s")
    image_positions = sorted(r["pos_image"] for r in hits)
    expect("the image phase alone ranks them 1-4 as well (where the time goes)",
           image_positions == [1, 2, 3, 4], f"positions {image_positions}")
    # How unlikely this is by luck: 4 named instances drawn at random land exactly in the top 4
    # with probability 1 / C(population, 4). Stated as context, not as a significance test.
    print(f"  chance of 4 random instances filling the top 4: 1 in {math.comb(population, 4):,}")

    # Negative controls: the two places an agent would look first, and why they find nothing.
    levels = db.query(
        "SELECT level, count(*) AS lines, count(DISTINCT instance_id) AS instances "
        "FROM os_ev WHERE list_contains(%s::VARCHAR[], instance_id) GROUP BY level ORDER BY level",
        [labels],
    )
    above_info = sum(r["lines"] for r in levels if r["level"] != "INFO")
    total_lines = sum(r["lines"] for r in levels)
    expect("a level filter cannot find them: all their lines are INFO",
           above_info == 0, f"{total_lines} lines, {above_info} above INFO")
    lat = {r["file_group"]: r for r in db.query(
        "SELECT file_group, api_calls, mean_s, p95_s FROM os_latency_by_file "
        "WHERE source_file = 'ALL' ORDER BY file_group")}
    a, n = lat["abnormal"], lat["normal"]
    gap = abs(float(a["mean_s"]) - float(n["mean_s"]))
    expect("a latency percentile cannot find them: the abnormal file's API latency matches",
           gap < 0.001,
           f"mean {float(a['mean_s']):.4f} vs {float(n['mean_s']):.4f} s, "
           f"p95 {float(a['p95_s']):.4f} vs {float(n['p95_s']):.4f} s "
           f"({a['api_calls']:,} vs {n['api_calls']:,} calls)")


# ------------------------------------------------------------------------------- BGL
# The majority label per signature. A tie has no majority, so it must not depend on scan order:
# arg_max picked either side of a 1-1 tie between runs (TP 348,455 one run, 348,454 the next).
# Ties go to '-', which sorts first: no majority, no alarm.
BGL_AGREEMENT = """
WITH s AS (
    SELECT signature, alert_category, count(*) AS n FROM bgl_sig GROUP BY signature, alert_category
), ranked AS (
    SELECT *, row_number() OVER (PARTITION BY signature ORDER BY n DESC, alert_category) AS k
    FROM s
), per_sig AS (
    SELECT signature, sum(n) AS lines, max(n) AS top_n, count(*) AS labels,
           max(alert_category) FILTER (WHERE k = 1) AS top_label,
           coalesce(sum(n) FILTER (WHERE alert_category <> '-'), 0) AS alert_lines
    FROM ranked GROUP BY signature
)
SELECT count(*)                                                   AS signatures,
       count(*) FILTER (WHERE labels > 1)                         AS mixed_signatures,
       sum(lines)                                                 AS lines,
       sum(top_n)                                                 AS majority_lines,
       sum(alert_lines)                                           AS alert_lines,
       coalesce(sum(alert_lines) FILTER (WHERE top_label <> '-'), 0)         AS tp,
       coalesce(sum(lines - alert_lines) FILTER (WHERE top_label <> '-'), 0) AS fp,
       coalesce(sum(alert_lines) FILTER (WHERE top_label = '-'), 0)          AS fn
FROM per_sig
"""

# The obvious label-free detector: the two top severities (BGL's alerts are all FATAL or FAILURE).
BGL_LEVEL = """
SELECT count(*) FILTER (WHERE is_alert AND level IN ('FATAL', 'FAILURE'))     AS tp,
       count(*) FILTER (WHERE NOT is_alert AND level IN ('FATAL', 'FAILURE')) AS fp,
       count(*) FILTER (WHERE is_alert AND level NOT IN ('FATAL', 'FAILURE')) AS fn
FROM bgl_ev
"""


def scores(tp: int, fp: int, fn: int) -> tuple[float, float, float]:
    p = tp / (tp + fp) if tp + fp else 0.0
    r = tp / (tp + fn) if tp + fn else 0.0
    return p, r, (2 * p * r / (p + r) if p + r else 0.0)


def bgl() -> None:
    print("\n2. BGL: does a text-only signature reproduce the expert label?")
    g = db.query(BGL_AGREEMENT)[0]
    g = {k: int(v) for k, v in g.items()}
    print(f"  {g['signatures']:,} signatures over {g['lines']:,} lines; "
          f"{g['mixed_signatures']} carry more than one label")
    print(f"  line agreement with the signature's majority label: "
          f"{pct(g['majority_lines'], g['lines'])} ({g['lines'] - g['majority_lines']} lines differ)")
    sp, sr, sf = scores(g["tp"], g["fp"], g["fn"])
    lv = {k: int(v) for k, v in db.query(BGL_LEVEL)[0].items()}
    lp, lr, lf = scores(lv["tp"], lv["fp"], lv["fn"])
    print(f"  {'detector':<34} {'TP':>9} {'FP':>9} {'FN':>6} {'precision':>10} {'recall':>9} {'F1':>8}")
    print(f"  {'signature majority is an alert':<34} {g['tp']:>9,} {g['fp']:>9,} {g['fn']:>6,} "
          f"{sp:>10.6f} {sr:>9.6f} {sf:>8.6f}")
    print(f"  {'level is FATAL or FAILURE':<34} {lv['tp']:>9,} {lv['fp']:>9,} {lv['fn']:>6,} "
          f"{lp:>10.6f} {lr:>9.6f} {lf:>8.6f}")
    expect("every alert line is counted once", g["alert_lines"] == 348_460, f"{g['alert_lines']:,}")
    expect("text-only signatures recover 348,454 of 348,460 alert lines with 3 false alarms",
           (g["tp"], g["fp"], g["fn"]) == (348_454, 3, 6),
           f"TP {g['tp']:,} FP {g['fp']} FN {g['fn']}")
    expect("only 4 of the signatures mix labels", g["mixed_signatures"] == 4,
           f"{g['mixed_signatures']} of {g['signatures']:,}")
    expect("the severity filter finds every alert but is wrong more often than right",
           lv["fn"] == 0 and lp < 0.5, f"recall {lr:.4f}, precision {lp:.4f}")
    mixed = db.query(
        """
        WITH s AS (SELECT signature, alert_category, count(*) AS n FROM bgl_sig
                   GROUP BY signature, alert_category),
             m AS (SELECT signature FROM s GROUP BY signature HAVING count(*) > 1)
        SELECT left(s.signature, 48) AS signature, alert_category, n
        FROM s JOIN m USING (signature) ORDER BY signature, n DESC, alert_category
        """
    )
    print("  the disagreements (label noise, not new faults):")
    for r in mixed:
        print(f"    {r['signature']:<48} {r['alert_category']:<10} {r['n']:>7,}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--labels", type=pathlib.Path, default=DEFAULT_LABELS,
                    help="path to anomaly_labels.txt (default: data/loghub/anomaly_labels.txt)")
    args = ap.parse_args()
    print("ground-truth validation | outside the agent: not an MCP tool, labels read from disk")
    print(f"  engine: {db.ping()}")
    out_of_reach()
    openstack(read_labels(args.labels))
    bgl()
    failed = [label for ok, label in _results if not ok]
    print(f"\n{len(_results) - len(failed)}/{len(_results)} expectations hold")
    print("validation: " + ("PASS" if not failed else "FAIL -- " + "; ".join(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
