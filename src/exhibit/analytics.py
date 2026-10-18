"""Stage 3: the analysis tools.

The thesis of Stage 3 is one sentence: **count incidents, not lines.** A line is evidence; an
incident is a signature x blast radius x persistence, and only the second one is what an on-call
engineer, a team lead or a manager can act on.

Every tool here answers a question about the *shape* of an outage, and every one of them runs under
the caller's database role, so the three personas get three genuinely different views of one corpus
-- enforced by grants, not by prose. Four things this module refuses to do on purpose:

* **invent a number.** Every figure comes back with the statement that produced it and an evidence
  id, and ``verify_evidence`` re-runs any of them on demand;
* **pretend a role has data it cannot read.** If a role's relation has no hourly bucket, ``trend``
  says so rather than summing something adjacent;
* **vary a parameter the data cannot vary.** The gap in ``episodes`` is a real parameter for the
  engineer, who holds a grant on the parsed relation; for the lead and the manager the 5-minute
  grouping is baked into the relation they are allowed to read, and the refusal says exactly that;
* **sum a number that is not additive.** `nodes` is distinct machines *per incident*; adding two
  incidents' node counts double-counts every machine in both, so blast radius is reported as a
  peak, and `count_events` carries the same warning in its notes.
"""
from __future__ import annotations

import math
from datetime import date, datetime
from decimal import Decimal
from typing import Any

import psycopg

from . import db, ledger
from .datasets import (
    BUCKETS,
    INDEX_COLUMNS,
    INDEX_GROUP,
    ORIGIN,
    change_of,
    durations_of,
    episodes_of,
    rank_of,
)
from .tools import (TEXT_CHARS, _agg, _asked, _as_dt, _envelope, _filters, _jsonable,
                    _refuse, _scope)

MAX_ROWS = 200           # rule 9: hard cap on returned rows
DEFAULT_ROWS = 20        # rule 9: default page size
MAX_BUCKETS = 400        # rule 9: hard cap on buckets in one trend
MAX_FACETS = 10          # rule 9: hard cap on facet values


def _clamp(n: Any, default: int = DEFAULT_ROWS, hard: int = MAX_ROWS) -> int:
    try:
        value = int(n)
    except (TypeError, ValueError):
        value = default
    return max(1, min(value, hard))


def _finish(tool: str, dataset_key: str, p, sql: str, params: list[Any], **kw) -> dict:
    """Build the envelope and record its evidence.

    A ledger write that fails must not eat the answer: a demo that dies because its bookkeeping
    failed is worse than one that admits the bookkeeping failed.

    ``full_rows`` is the statement's whole result when the envelope only shows a page of it --
    the ledger stores the hash of what a re-run would return, not of the page.

    Rows are normalised to JSON-safe values here, once, for every tool.
    """
    full_rows = kw.pop("full_rows", None)
    if full_rows is not None:
        full_rows = [{k: _jsonable(v) for k, v in row.items()} for row in full_rows]
    env = _envelope(tool, dataset_key, p, sql, params=params, **kw)
    try:
        ledger.record(env, sql, params, rows=full_rows)
        env["ledger"] = f"recorded as {env['evidence_id']}"
    except Exception as exc:                     # noqa: BLE001 - deliberately broad, see above
        env["ledger"] = f"not recorded: {type(exc).__name__}"
        env["notes"].append(
            f"the evidence ledger write failed ({exc}); the statement above is still the answer "
            f"and re-running it by hand reproduces these rows"
        )
    return env


def _refused(tool: str, dataset_key: str, p, reason: str, scope: dict) -> dict:
    """A refusal is an answer, and it is evidence too -- so it is recorded like one."""
    env = _refuse(tool, dataset_key, p, reason, scope)
    try:
        ledger.record(env, env["query"], [])
        env["ledger"] = f"recorded as {env['evidence_id']}"
    except Exception as exc:                     # noqa: BLE001
        env["ledger"] = f"not recorded: {type(exc).__name__}"
    return env


def _no_dataset(dataset: str, p) -> dict:
    return {
        "tool": "", "dataset": dataset, "persona": p.key, "role": p.role, "refused": True,
        "measure": None, "scope": {"dataset": dataset}, "evidence_id": "", "total_matches": None,
        "returned": 0, "truncated": False, "operator": "", "columns": [], "rows": [],
        "query": "-- refused before any SQL ran", "notes": [],
    }


# =========================================================================== episodes
def episodes(
    dataset: str,
    persona: str | None = None,
    gap_minutes: int = 5,
    coalesce_by: str | None = None,
    signature: str | None = None,
    limit: int = DEFAULT_ROWS,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> dict:
    """Collapse lines into incidents, and show what the collapse costs.

    An incident is one signature, in one failure domain, that did not go quiet for longer than
    ``gap_minutes``. The gap is the tool's most important parameter and the one most often left
    implicit: the same corpus reads as 22,002 incidents at a 1-minute gap and 14,479 at an hour.
    Whatever gap you pass is stated back to you, because a count without its gap is a number
    without a meaning.
    """
    p = _asked(persona)
    key = dataset.strip().lower()
    view = p.views.get(key)
    scope = _scope(dataset, gap_minutes=gap_minutes, coalesce_by=coalesce_by or "",
                   signature=signature or "", since=since, until=until, level=level, team=team)
    if view is None:
        return _refused("episodes", dataset, p,
                        f"{p.key} cannot read {dataset!r}; readable: {', '.join(p.datasets)}", scope)
    try:
        src = episodes_of(p.key, key)
    except KeyError as exc:
        return _refused("episodes", dataset, p, str(exc), scope)

    gap = _clamp(gap_minutes, default=5, hard=1440)
    limit = _clamp(limit)
    name = coalesce_by or src.default_partition
    if name not in src.partitions:
        return _refused("episodes", dataset, p,
                        f"coalesce_by must be one of: {', '.join(sorted(src.partitions))}", scope)
    if signature and not src.key_column:
        return _refused(
            "episodes", dataset, p,
            f"{p.key} cannot filter by signature text: {src.relation} names problems by "
            f"{src.partitions[name][0]}, which is a key rather than log text. Filter on that key.",
            scope)

    if src.kind == "precomputed":
        if src.gap_minutes is not None and gap != src.gap_minutes:
            return _refused(
                "episodes", dataset, p,
                f"{p.key} reads {src.relation}, where incidents are already grouped at a "
                f"{src.gap_minutes}-minute gap, so the gap is not a parameter for this role. The "
                f"engineer reads the parsed relation and can vary it.", scope)
        return _episodes_stored(p, key, src, name, limit, scope, since, until, team,
                                signature=signature)

    parts = list(src.partitions[name])
    part_sql = ", ".join(parts)
    order_sql = ", ".join(src.order)
    cols = list(dict.fromkeys([*parts, *src.display]))
    sel = ", ".join(cols)
    extra = [src.node_source] if src.node_source not in cols else []
    # the ORDER BY columns must be in scope: OpenStack orders by (ts, id), BGL by ts alone
    extra += [c for c in src.order if c not in cols and c not in extra]

    params: list[Any] = [gap]
    clauses = [src.filter_sql] if src.filter_sql else []
    clauses += _filters(view, params, since=since, until=until, level=level, team=team)
    if signature:
        clauses.append(f"{src.key_column} = %s")
        params.append(signature)
    where = f" WHERE {' AND '.join(clauses)}" if clauses else ""
    select_cols = ", ".join(dict.fromkeys([sel, *extra]))

    sql = f"""WITH marked AS (
    SELECT {select_cols},
           CASE WHEN LAG(ts) OVER (PARTITION BY {part_sql} ORDER BY {order_sql}) IS NULL
                  OR ts - LAG(ts) OVER (PARTITION BY {part_sql} ORDER BY {order_sql})
                     > INTERVAL '1 minute' * %s
                THEN 1 ELSE 0 END AS is_new
    FROM {src.relation}{where}
),
numbered AS (
    SELECT *, SUM(is_new) OVER (PARTITION BY {part_sql} ORDER BY {order_sql}
                                ROWS UNBOUNDED PRECEDING) AS episode_no
    FROM marked
)
SELECT {sel}, episode_no, count(*) AS lines, {src.nodes} AS nodes,
       min(ts) AS started, max(ts) AS ended, max(ts) - min(ts) AS span
FROM numbered
GROUP BY {sel}, episode_no
ORDER BY lines DESC, started, {part_sql}"""

    rows = db.query(sql, params, role=p.role)
    total = len(rows)                     # one row per incident: the row count IS the episode count
    shown = rows[:limit]
    line_total = sum(int(r["lines"]) for r in rows)

    notes = [
        f"one row = one incident: {part_sql} that did not fall quiet for more than {gap} minute(s)",
        f"{line_total:,} lines collapse into {total:,} incidents at this gap — volume overstates "
        f"incidents roughly {line_total / total:,.0f}x here",
        f"the gap is a real parameter for {p.key} because {p.key} reads {src.relation}; "
        f"recomputed here rather than read from a prebuilt view",
        src.note,
        f"read as {p.role}",
    ]
    # a measured zero is still a claim, and this one reads like a defect: say what it means.
    # The OpenStack corpus writes 'NONE' into the instance column for any line that has no
    # instance context (host-level warnings, for instance), so a problem whose lines are all
    # sentinels has a blast radius that is *unmeasurable in instances*, which is not the same
    # as zero impact — the affected host still matters.
    zero_blast = [r for r in rows if not int(r.get("nodes") or 0)]
    if zero_blast:
        notes.append(
            f"{len(zero_blast)} of {total:,} incidents report 0 nodes: every line behind them "
            f"carries no instance id in the corpus (the 'NONE' sentinel), so the blast radius is "
            f"unmeasurable in instances rather than genuinely zero — read the service and the "
            f"file paths instead, and do not report 'no impact'"
        )
    return _finish("episodes", key, p, sql, params, scope=scope, rows=shown, total_matches=total,
                   full_rows=rows,
                   columns=[*cols, "episode_no", "lines", "nodes", "started", "ended", "span"],
                   notes=notes, measure=None)


def _episodes_stored(p, key: str, src, name: str, limit: int, scope: dict,
                     since, until, team, signature: str | None = None) -> dict:
    """The lead's and manager's episode counts: already grouped, at the gap that relation states."""
    if (since or until) and not src.time_column:
        # mgr_*_risk carries first_seen, but its incident counts are per-problem all-time totals --
        # a window cannot narrow them, and filtering by first_seen would silently answer a
        # different question ("problems first seen in this window") than the one asked.
        return _refused(
            "episodes", key, p,
            f"incidents here are precomputed per problem across the whole corpus ({src.relation} "
            f"carries no incident-start column), so since/until cannot narrow the count -- it is "
            f"all-time. Ask the engineer (or the lead, whose relation carries `started`) for a "
            f"windowed incident count.", scope)
    params: list[Any] = []
    clauses: list[str] = []
    if (since_dt := _as_dt(since)) is not None and src.time_column:
        clauses.append(f"{src.time_column} >= %s::timestamp")
        params.append(since_dt)
    if (until_dt := _as_dt(until)) is not None and src.time_column:
        clauses.append(f"{src.time_column} < %s::timestamp")
        params.append(until_dt)
    if team:
        clauses.append("team = %s")
        params.append(team.lower())
    if signature and src.key_column:
        clauses.append(f"{src.key_column} = %s")
        params.append(signature)
    where = f" WHERE {' AND '.join(clauses)}" if clauses else ""
    gap_note = (f"incidents are already grouped at a {src.gap_minutes}-minute gap in "
                f"{src.relation}; the gap is not a parameter for this role")

    if src.count_column:
        # the manager: one row per problem, already counted
        spec = rank_of(p.key, key)
        grain = ", ".join(spec.grain or (spec.key,))
        sql = (f"SELECT {grain}, {spec.lines} AS lines, {spec.episodes} AS episodes,"
               f" {spec.nodes} AS nodes FROM {src.relation}{where}"
               f" GROUP BY {grain} ORDER BY episodes DESC")
        rows = db.query(sql, params, role=p.role)
        total = sum(int(r["episodes"] or 0) for r in rows)
        shown = rows[:limit]
        notes = [
            gap_note,
            f"{total:,} incidents across {len(rows):,} groups by {spec.key}; "
            f"episodes are summed, lines are summed, blast radius is the peak — never added up",
            spec.note, src.note, f"read as {p.role}",
        ]
        cols = [*(spec.grain or (spec.key,)), "lines", "episodes", "nodes"]
    else:
        cols = list(dict.fromkeys([*src.partitions[name], *src.display]))
        sel = ", ".join(cols)
        sql = (f"SELECT {sel}, episode_no, lines, {src.nodes_column} AS nodes, started, ended, span"
               f" FROM {src.relation}{where} ORDER BY lines DESC")
        rows = db.query(sql, params, role=p.role)
        total = len(rows)
        shown = rows[:limit]
        line_total = sum(int(r["lines"]) for r in rows)
        notes = [
            gap_note,
            f"{total:,} incidents carrying {line_total:,} lines — the incidents are rows here, so "
            f"this role sees the collapse already done rather than doing it",
            src.note, f"read as {p.role}",
        ]
        cols = [*cols, "episode_no", "lines", "nodes", "started", "ended", "span"]

    return _finish("episodes", key, p, sql, params, scope=scope, rows=shown, total_matches=total,
                   full_rows=rows, columns=cols, notes=notes)


# =========================================================================== top_signatures
def top_signatures(
    dataset: str,
    persona: str | None = None,
    by: str = "episodes",
    gap_minutes: int = 5,
    limit: int = DEFAULT_ROWS,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> dict:
    """Rank problems, showing lines, incidents and blast radius side by side.

    This is the tool that makes the project's main finding checkable: rank this corpus by lines and
    you get a fleet-wide log flood; rank it by blast radius or persistence and a six-hour,
    one-machine meltdown comes to the top. ``by`` chooses which column the ordering uses — the
    other two come back anyway, so the disagreement between them is visible in the same table.
    """
    p = _asked(persona)
    key = dataset.strip().lower()
    view = p.views.get(key)
    scope = _scope(dataset, rank_by=by, gap_minutes=gap_minutes, since=since, until=until,
                   level=level, team=team)
    if view is None:
        return _refused("top_signatures", dataset, p,
                        f"{p.key} cannot read {dataset!r}; readable: {', '.join(p.datasets)}", scope)
    try:
        spec = rank_of(p.key, key)
    except KeyError as exc:
        return _refused("top_signatures", dataset, p, str(exc), scope)

    metric = (by or "episodes").strip().lower()
    if metric not in ("episodes", "lines", "nodes"):
        if metric == spec.node_label:
            return _refused("top_signatures", dataset, p,
                            f"by must be one of: episodes, lines, nodes -- this relation's "
                            f"blast-radius column is {spec.node_label} (requests affected, not "
                            f"machines), and by='nodes' is how you order by it", scope)
        return _refused("top_signatures", dataset, p,
                        "by must be one of: episodes, lines, nodes", scope)
    if metric == "nodes" and spec.nodes_unmeasurable:
        # measured, not assumed: this dataset's problem lines carry no instance id at all
        return _refused("top_signatures", dataset, p, spec.nodes_unmeasurable, scope)
    limit = _clamp(limit)
    # `by=nodes` must order by the column's *output* name, not the logical one: some relations
    # rename it (the OpenStack manager's blast radius counts requests_affected, not machines), and
    # ordering by the logical name "nodes" against such a relation is a column-not-found error.
    order_by = spec.node_label if metric == "nodes" else metric
    grain = list(spec.grain or (spec.key,))
    grain_sql = ", ".join(grain)
    cols = list(dict.fromkeys([*grain, *spec.extra]))

    params: list[Any] = []
    clauses = [spec.filter_sql] if spec.filter_sql else []
    clauses += _filters(view, params, since=since, until=until, level=level, team=team,
                        time_column=spec.time_column or None)
    where = f" WHERE {' AND '.join(clauses)}" if clauses else ""

    if spec.episodes and "(" in (spec.episodes or ""):
        # stored aggregate (lead and manager): the incidents are already counted in the relation
        sel = ", ".join([grain_sql, *spec.extra]) if spec.extra else grain_sql
        sql = (f"SELECT {sel}, {spec.lines} AS lines, {spec.episodes} AS episodes,"
               f" {spec.nodes} AS {spec.node_label} FROM {spec.relation}{where}"
               f" GROUP BY {sel} ORDER BY {order_by} DESC NULLS LAST, {grain_sql} LIMIT %s")
        rows = db.query(sql, [*params, limit], role=p.role)
        total = db.scalar(
            f"SELECT count(*) FROM (SELECT {sel} FROM {spec.relation}{where} GROUP BY {sel}) g",
            params, role=p.role)
        notes = [
            f"ranked by {metric}; lines, episodes and blast radius all returned so the ranking "
            f"criteria can disagree in front of you",
            f"blast radius is the PEAK distinct count, not a sum — adding node counts across "
            f"incidents double-counts every machine in both",
            spec.note, f"read as {p.role}",
            *( [f"gap fixed at {spec.fixed_gap} minutes by this role's relation"]
               if spec.fixed_gap else [] ),
        ]
        final_params = [*params, limit]
    else:
        # computed (engineer): episodes are coalesced in-query at the requested gap
        gap = _clamp(gap_minutes, default=5, hard=1440)
        node_extra = [spec.node_source] if spec.node_source and spec.node_source not in cols else []
        select_cols = ", ".join(dict.fromkeys([*cols, *node_extra, "ts"]))
        sql = f"""WITH marked AS (
    SELECT {select_cols},
           CASE WHEN LAG(ts) OVER (PARTITION BY {grain_sql} ORDER BY ts) IS NULL
                  OR ts - LAG(ts) OVER (PARTITION BY {grain_sql} ORDER BY ts)
                     > INTERVAL '1 minute' * %s
                THEN 1 ELSE 0 END AS is_new
    FROM {spec.relation}{where}
),
numbered AS (
    SELECT *, SUM(is_new) OVER (PARTITION BY {grain_sql} ORDER BY ts
                                ROWS UNBOUNDED PRECEDING) AS episode_no
    FROM marked
)
SELECT {", ".join(cols)}, count(*) AS lines, count(DISTINCT episode_no) AS episodes,
       {spec.nodes} AS {spec.node_label}
FROM numbered
GROUP BY {", ".join(cols)}
ORDER BY {order_by} DESC NULLS LAST, {", ".join(cols)}
LIMIT %s"""
        rows = db.query(sql, [gap, *params, limit], role=p.role)
        total = db.scalar(
            f"SELECT count(*) FROM (SELECT {', '.join(cols)} FROM {spec.relation}{where}"
            f" GROUP BY {', '.join(cols)}) g", params, role=p.role)
        notes = [
            f"ranked by {metric}; episodes coalesced in-query at a {gap}-minute gap",
            f"grain = {grain_sql}: the same key an incident is coalesced at, so 'episodes' here is "
            f"a count of real incidents and not of rows that happen to share a label",
            f"blast radius is the PEAK distinct count, never a sum",
            spec.note, f"read as {p.role}",
        ]
        final_params = [gap, *params, limit]

    return _finish("top_signatures", key, p, sql, final_params, scope=scope,
                   rows=rows, total_matches=total,
                   columns=[*cols, "lines", "episodes", spec.node_label], notes=notes)


# =========================================================================== trend
def trend(
    dataset: str,
    persona: str | None = None,
    bucket: str = "day",
    days: int | None = None,
    limit: int = MAX_BUCKETS,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> dict:
    """How a number moved over time, in buckets, anchored to the data's own clock.

    ``days`` is measured back from the **last timestamp in the corpus**, not from today: this data
    is from 2005 and 2017, so a window computed against "now" would silently return nothing.
    """
    p = _asked(persona)
    key = dataset.strip().lower()
    view = p.views.get(key)
    name = (bucket or "day").strip().lower()
    scope = _scope(dataset, bucket=name, days=days, since=since, until=until, level=level, team=team)
    if view is None:
        return _refused("trend", dataset, p,
                        f"{p.key} cannot read {dataset!r}; readable: {', '.join(p.datasets)}", scope)
    if name not in BUCKETS:
        return _refused("trend", dataset, p,
                        f"bucket must be one of: {', '.join(BUCKETS)}", scope)

    limit = _clamp(limit, default=MAX_BUCKETS, hard=MAX_BUCKETS)
    tc = view.time_column
    params: list[Any] = []
    clauses = _filters(view, params, since=since, until=until, level=level, team=team)

    if days is not None:
        last = db.scalar(f"SELECT max({tc}) FROM {view.relation}", role=p.role)
        if last is not None:
            clauses.append(f"{tc} >= %s::timestamp - INTERVAL '1 day' * %s")
            params.extend([last, _clamp(days, default=7, hard=3650)])
    where = f" WHERE {' AND '.join(clauses)}" if clauses else ""

    if tc == "ts":
        bucket_expr = f"date_bin(INTERVAL '1 hour' * %s, {tc}, {ORIGIN.get(key, ORIGIN['bgl'])})"
        params.insert(0, BUCKETS[name])
        grain = "the corpus's own start, so buckets are aligned across datasets"
    elif tc in ("day", "hour"):
        if name != tc:
            return _refused(
                "trend", dataset, p,
                f"{p.key}'s view for {key} is bucketed by {tc} ({view.relation}), so a "
                f"'{name}' trend cannot be produced from it. Ask for bucket='{tc}'.", scope)
        bucket_expr = tc
        grain = f"the {tc} column this role's relation already carries"
    else:
        return _refused(
            "trend", dataset, p,
            f"{p.key}'s view for {key} ({view.relation}) carries no time bucket, so there is no "
            f"trend to show for this role on this dataset.", scope)

    agg = _agg(view)
    source = view.relation
    # newest buckets first inside SQL, so the cap keeps the *recent* history, then re-sorted
    sql = (f"SELECT {bucket_expr} AS bucket, {agg} AS n FROM {source}{where}"
           f" GROUP BY 1 ORDER BY 1 DESC LIMIT %s")
    rows = db.query(sql, [*params, limit], role=p.role)
    statement_rows = list(rows)          # the order the statement returned: what a re-run reproduces
    rows.reverse()                       # a trend reads left to right

    notes = [
        f"bucketed by {name}; {grain}",
        "n = count(*) of rows" if view.is_raw else f"n = sum({view.measure}) of this role's measure",
        "the window is anchored to the last timestamp in the data, never to today",
        f"read as {p.role}",
    ]
    return _finish("trend", key, p, sql, [*params, limit], scope=scope, rows=rows,
                   total_matches=len(rows), full_rows=statement_rows, columns=["bucket", "n"],
                   notes=notes, measure=view.measure)


# =========================================================================== durations
def durations(
    dataset: str = "openstack",
    persona: str | None = None,
    by: str = "spawn_s",
    limit: int = DEFAULT_ROWS,
    team: str | None = None,
) -> dict:
    """Where time actually went: server lifecycle phases, worst first.

    OpenStack only — BGL is a kernel log with no lifecycle to time. This is also the only place the
    four labelled anomalies in ``anomaly_labels.txt`` are visible at all: they log at INFO, their
    aggregate latency matches the normal files, and only the phase timings separate them.
    """
    p = _asked(persona)
    key = dataset.strip().lower()
    scope = _scope(dataset, phase=by, team=team)
    if key != "openstack":
        return _refused(
            "durations", dataset, p,
            f"{key} has no lifecycle durations: this tool reads OpenStack server timings. BGL is a "
            f"kernel log — use episodes or trend for it.", scope)
    try:
        src = durations_of(p.key)
    except KeyError as exc:
        return _refused("durations", dataset, p, str(exc), scope)

    phase = (by or "spawn_s").strip().lower()
    if phase not in src.phases:
        return _refused(
            "durations", dataset, p,
            f"{p.key} cannot rank by {phase!r}; this role's relation ({src.relation}) carries: "
            f"{', '.join(src.phases)}", scope)
    limit = _clamp(limit)

    params: list[Any] = []
    clauses = ["team = %s"] if team else []
    if team:
        params.append(team.lower())
    where = f" WHERE {' AND '.join(clauses)}" if clauses else ""
    sel = ", ".join([src.key, *src.extra])
    # Ties fall back to the key so the order is total: 292 distinct spawn_s values over 2,066
    # instances means tied rows would otherwise swap between runs and a stored hash could stop
    # matching. (NULLS LAST is this engine's default even under DESC; writing it keeps the
    # statement portable.)
    sql = (f"SELECT {sel}, {phase} AS ranked_by FROM {src.relation}{where}"
           f" ORDER BY {phase} DESC NULLS LAST, {src.key} LIMIT %s")
    rows = db.query(sql, [*params, limit], role=p.role)
    total = db.scalar(f"SELECT count(*) FROM {src.relation}{where}", params, role=p.role)

    notes = [
        f"ranked by {phase}, worst first — {src.relation}",
        src.note,
        f"total rows in this relation: {total:,}",
        f"read as {p.role}",
    ]
    return _finish("durations", key, p, sql, [*params, limit], scope=scope, rows=rows,
                   total_matches=total, columns=[src.key, *src.extra, "ranked_by"], notes=notes)


# =========================================================================== ownership
def ownership(
    persona: str | None = None,
    dataset: str | None = None,
    team: str | None = None,
    limit: int = 100,
) -> dict:
    """Who owns what — and whether anything is unowned.

    The brief asks for a team-ownership table that the competition does not supply, so we built one
    (``data/ownership.csv`` -> ``owner_map``). This tool reads it back, and *checks* it against the
    corpus rather than trusting it: every key in the logs is looked up, and anything unmapped is
    reported as unowned instead of being quietly dropped.
    """
    p = _asked(persona)
    scope = _scope(dataset or "-", team=team)
    limit = _clamp(limit, default=100)
    params: list[Any] = []
    clauses = []
    if dataset:
        clauses.append("lower(dataset) = %s")
        params.append(dataset.strip().lower())
    if team:
        clauses.append("team = %s")
        params.append(team.lower())
    where = f" WHERE {' AND '.join(clauses)}" if clauses else ""
    sql = (f"SELECT dataset, key_type, key_value, team FROM owner_map{where}"
           f" ORDER BY dataset, key_type, key_value LIMIT %s")
    try:
        rows = db.query(sql, [*params, limit], role=p.role)
    except psycopg.errors.InsufficientPrivilege:
        return _refused(
            "ownership", dataset or "-", p,
            f"{p.key} has no grant on owner_map: the ownership table is an engineer's and a team "
            f"lead's working document. This role's own views carry `team` on every row instead, so "
            f"ownership arrives with the number rather than as a separate lookup.", scope)
    total = db.scalar(f"SELECT count(*) FROM owner_map{where}", params, role=p.role)

    covered: list[dict] = []
    for ds in ([dataset.strip().lower()] if dataset else p.datasets):
        v = p.views.get(ds)
        if v is None:
            continue
        covered.append({
            "dataset": ds,
            "relation": v.relation,
            "lines_by_team": db.query(
                f"SELECT team, {_agg(v)} AS n FROM {v.relation} GROUP BY 1 ORDER BY 2 DESC",
                role=p.role),
        })
    unmapped = db.scalar(
        "SELECT count(*) FROM (SELECT DISTINCT team FROM owner_map) t WHERE team IS NULL")
    seen = {r["team"] for grp in covered for r in grp["lines_by_team"]}
    known = {r["team"] for r in db.query("SELECT DISTINCT team FROM owner_map", role=p.role)}
    unknown_teams = sorted(seen - known)

    notes = [
        f"{total:,} ownership rows; {len(covered)} readable dataset(s) checked against them",
        f"every key in the corpus resolves to a team: {len(unknown_teams)} unowned"
        if not unknown_teams else f"UNOWNED keys present in the data: {', '.join(unknown_teams)}",
        "the check runs against the corpus itself, so a rule change that orphans a key shows up "
        "here rather than in a slide",
        f"read as {p.role}",
    ]
    return _finish("ownership", dataset or ", ".join(p.datasets), p, sql, [*params, limit],
                   scope=scope, rows=rows, total_matches=total,
                   columns=["dataset", "key_type", "key_value", "team"], notes=notes)


# =========================================================================== nearby_events
def nearby_events(
    dataset: str,
    persona: str | None = None,
    ts: str | None = None,
    id: int | None = None,
    minutes: int = 15,
    limit: int = DEFAULT_ROWS,
) -> dict:
    """What else was happening around a given line — the second question on every incident call.

    Engineer only: it reads the index relation directly. Anchor on a line id (preferred, because it
    is exact) or on a timestamp, and it returns the window either side plus what else fired in it,
    so "the disk failed" can be read as "the disk failed while the fence agent was flapping".
    """
    p = _asked(persona)
    key = dataset.strip().lower()
    view = p.views.get(key)
    window = _clamp(minutes, default=15, hard=720)
    scope = _scope(dataset, id=id, ts=ts, minutes=window)
    if view is None:
        return _refused("nearby_events", dataset, p,
                        f"{p.key} cannot read {dataset!r}; readable: {', '.join(p.datasets)}", scope)
    if not view.search:
        return _refused(
            "nearby_events", dataset, p,
            f"this tool walks the log line by line and {p.key} has no grant on an index relation "
            f"({view.relation} is aggregated), so there are no individual events to walk. Use "
            f"episodes or top_signatures for the incident-level answer.", scope)
    if id is None and not ts:
        return _refused("nearby_events", dataset, p,
                        "give either id (a log line id) or ts (an anchor timestamp)", scope)

    source = view.search
    tc, idc = view.time_column, view.id_column
    params: list[Any] = []
    if id is not None:
        anchor = db.scalar(f"SELECT {tc} FROM {source} WHERE {idc} = %s LIMIT 1", [int(id)],
                           role=p.role)
        if anchor is None:
            return _refused("nearby_events", dataset, p,
                            f"no line with {idc} = {id} in {source}", scope)
    else:
        anchor = _as_dt(ts)

    params.extend([anchor, window, anchor, window])
    where = (f"{tc} >= %s::timestamp - INTERVAL '1 minute' * %s AND "
             f"{tc} <= %s::timestamp + INTERVAL '1 minute' * %s")
    cols = [c for c in INDEX_COLUMNS.get(key, ()) if c] or [idc, tc, view.level_column, "team"]
    sel = ", ".join(dict.fromkeys(cols))
    sql = (f"SELECT {sel}, left({view.search_column}, {TEXT_CHARS}) AS content FROM {source}"
           f" WHERE {where} ORDER BY {tc} LIMIT %s")
    rows = db.query(sql, [*params, limit], role=p.role)
    total = db.scalar(f"SELECT count(*) FROM {source} WHERE {where}", params, role=p.role)

    group_col = INDEX_GROUP.get(key, "team")
    around = db.query(
        f"SELECT {group_col} AS dimension, count(*) AS lines FROM {source} WHERE {where}"
        f" GROUP BY 1 ORDER BY 2 DESC LIMIT %s", [*params, MAX_FACETS], role=p.role)
    id_range = db.query(f"SELECT min({idc}) AS lo, max({idc}) AS hi FROM {source} WHERE {where}",
                        params, role=p.role)[0]

    notes = [
        f"window: {window} minute(s) either side of {anchor} ({id_range['lo']}..{id_range['hi']} by id)",
        f"{total:,} lines in the window; busiest {group_col}: "
        + "; ".join(f"{r['dimension']} ({r['lines']})" for r in around),
        f"text is cut to {TEXT_CHARS} characters — the line, not the stack trace",
        f"read as {p.role}",
    ]
    env = _finish("nearby_events", key, p, sql, [*params, limit], scope={**scope, "anchor": str(anchor)},
                  rows=rows, total_matches=total, columns=[*cols, "content"], notes=notes)
    env["window_summary"] = around
    return env


# =========================================================================== what_changed
def what_changed(
    dataset: str,
    persona: str | None = None,
    window_hours: int = 6,
    baseline_hours: int = 24,
    min_lines: int = 1,
    limit: int = DEFAULT_ROWS,
) -> dict:
    """Foreground window against a baseline, rate-normalised, anchored to the data's last line.

    A raw ratio of counts is a trap here: a 6-hour window compared against 24 hours shows almost
    every signature "down 75%" purely because the window is shorter, so the comparison is per hour
    on both sides. ``rate_ratio`` above 1 means the signature is arriving faster than in the
    baseline; ``is_new`` means it was absent from the baseline altogether.
    """
    p = _asked(persona)
    key = dataset.strip().lower()
    scope = _scope(dataset, window_hours=window_hours, baseline_hours=baseline_hours,
                   min_lines=min_lines)
    try:
        spec = change_of(p.key, key)
    except KeyError as exc:
        return _refused("what_changed", dataset, p, str(exc), scope)
    limit = _clamp(limit)

    unit = "day" if spec.granularity == "day" else "hour"
    w = _clamp(window_hours, default=6, hard=24 * 60) / 24 if unit == "day" else window_hours
    b = _clamp(baseline_hours, default=24, hard=24 * 60) / 24 if unit == "day" else baseline_hours
    w = max(1, math.ceil(w)) if unit == "day" else max(1, int(w))
    b = max(1, math.ceil(b)) if unit == "day" else max(1, int(b))

    clauses = [spec.filter_sql] if spec.filter_sql else []
    if clauses:
        clauses = [f"({c})" for c in clauses]
    filt = f" AND {' AND '.join(clauses)}" if clauses else ""
    anchor = db.scalar(f"SELECT max({spec.time_column}) FROM {spec.relation}"
                       f" WHERE 1 = 1{filt}".replace("WHERE 1 = 1 AND", "WHERE"), role=p.role)
    if anchor is None:
        return _refused("what_changed", dataset, p,
                        f"{spec.relation} holds no rows this role can read", scope)

    sql = f"""WITH foreground AS (
    SELECT {spec.key} AS dimension, {spec.measure} AS n
    FROM {spec.relation}
    WHERE {spec.time_column} >= %s::timestamp - INTERVAL '1 {unit}' * %s AND {spec.time_column} < %s::timestamp{filt}
    GROUP BY 1
),
baseline AS (
    SELECT {spec.key} AS dimension, {spec.measure} AS n
    FROM {spec.relation}
    WHERE {spec.time_column} >= %s::timestamp - INTERVAL '1 {unit}' * %s AND {spec.time_column} < %s::timestamp - INTERVAL '1 {unit}' * %s{filt}
    GROUP BY 1
)
SELECT coalesce(foreground.dimension, baseline.dimension) AS dimension,
       coalesce(foreground.n, 0) AS foreground,
       coalesce(baseline.n, 0) AS baseline,
       CASE WHEN coalesce(baseline.n, 0) = 0 THEN TRUE ELSE FALSE END AS is_new,
       round(coalesce(foreground.n, 0) * 1.0 * %s
             / nullif(coalesce(baseline.n, 0) * 1.0 * %s, 0), 2) AS rate_ratio
FROM foreground FULL OUTER JOIN baseline ON foreground.dimension = baseline.dimension
WHERE coalesce(foreground.n, 0) >= %s
ORDER BY is_new DESC, rate_ratio DESC, foreground DESC
LIMIT %s"""
    params = [anchor, w, anchor, anchor, w + b, anchor, w, b, w, min_lines, limit]
    rows = db.query(sql, params, role=p.role)

    notes = [
        f"foreground: the last {w} {unit}(s) before {anchor} ({spec.measure})",
        f"baseline: the {b} {unit}(s) before that; both sides are compared per {unit}, so a shorter "
        f"window does not read as a decline",
        "anchor = the last timestamp in the data, never today",
        spec.note,
        f"is_new = absent from the baseline; rate_ratio > 1 = arriving faster than baseline; "
        f"NULL rate_ratio with is_new false means the baseline was zero on both sides",
        f"read as {p.role}",
    ]
    return _finish("what_changed", key, p, sql, params, scope={**scope, "anchor": str(anchor)},
                   rows=rows, total_matches=len(rows),
                   columns=["dimension", "foreground", "baseline", "is_new", "rate_ratio"],
                   notes=notes)


# =========================================================================== verify_evidence
def verify_evidence(evidence_id: str, sample: int = 3) -> dict:
    """Re-run a stored answer and compare it to what was recorded.

    The credibility move of the whole project: no number here is taken on trust, including the ones
    this server produced. Ask for an evidence id (every answer prints one) and this re-executes the
    exact statement, under the exact role, with the exact parameters, and compares hashes.
    """
    eid = (evidence_id or "").strip().upper()
    if not eid:
        raise ValueError("give an evidence id, e.g. E-1A2B3C; every answer prints one")
    try:
        result = ledger.verify(eid, sample=_clamp(sample, default=3, hard=20))
        for field, value in list(result.items()):
            if isinstance(value, list) and value and isinstance(value[0], dict):
                result[field] = [{k: _jsonable(v) for k, v in row.items()} for row in value]
        result["ledger_size"] = ledger.count()
        result["evidence_ids_recent"] = [r["evidence_id"] for r in ledger.entries(limit=10)]
    except psycopg.errors.UndefinedTable:
        return {
            "evidence_id": eid,
            "match": None,
            "verdict": (
                "NO LEDGER - this database has no exhibit_evidence table, so there is nothing to "
                "verify against yet. The table is created by sql/55_evidence.sql: run `make "
                "evidence` (or `make bootstrap`) and ask again."
            ),
            "note": "only happens on a database bootstrapped before sql/55_evidence.sql existed",
        }
    result["note"] = (
        "a mismatch is not a bug in the ledger — it means the corpus or the definition moved since "
        "the answer was given, which is what a reader wants to know"
    )
    return result
