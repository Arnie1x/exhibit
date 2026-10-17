"""The Stage 2 tools: describe_data, search_logs, count_events.

Design rules, all of them learned the hard way (see docs/capabilities.md):

* full-text predicates run against ``dataset.index`` and nothing else -- a plain derived table
  refuses ``@@`` even with an index attached;
* the un-truncated total comes from its own COUNT over exactly the same WHERE clause, so
  ``truncated`` is a fact rather than a guess;
* every tool states which operator produced its numbers, because ``@@ 'base'``, a
  non-alpha-splitter index and ``ILIKE`` give three different counts on the same data.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Sequence

from . import db
from .datasets import REGISTRY, Dataset, resolve
from .envelope import Envelope

MODES = {
    "term": ("%s", "term match (@@)"),
    "phrase": ("ts_phrase(%s)", "phrase (ts_phrase)"),
    "any": ("ts_any(%s::TSQUERY[])", "any-of (ts_any)"),
    "all": ("ts_all(%s::TSQUERY[])", "all-of (ts_all)"),
}


def _as_dt(value) -> datetime | None:
    if value in (None, ""):
        return None
    if isinstance(value, datetime):
        return value
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))


def _predicate(dataset: Dataset, query: str, mode: str, params: list) -> tuple[str, str]:
    """Return (sql fragment, human name of the operator)."""
    mode = (mode or "phrase").strip().lower()
    if mode not in MODES:
        raise ValueError(f"unknown mode {mode!r}; available: {', '.join(sorted(MODES))}")
    if mode in ("any", "all"):
        terms = [t.strip() for t in query.split(",") if t.strip()]
        params.append(terms)
    else:
        params.append(query)
    fragment, label = MODES[mode]
    return f"{dataset.search_column} @@ {fragment}", label


def _filters(dataset: Dataset, params: list, *, since=None, until=None, level=None, team=None) -> list[str]:
    clauses: list[str] = []
    if (since_dt := _as_dt(since)) is not None:
        clauses.append(f"{dataset.time_column} >= %s")
        params.append(since_dt)
    if (until_dt := _as_dt(until)) is not None:
        clauses.append(f"{dataset.time_column} < %s")
        params.append(until_dt)
    if level:
        clauses.append(f"{dataset.level_column} = %s")
        params.append(level.upper())
    if team:
        clauses.append(f"{dataset.owner_key} = %s")
        params.append(team.lower())
    return clauses


def _scope(dataset: Dataset, **kw) -> dict[str, Any]:
    return {"dataset": dataset.key, **{k: v for k, v in kw.items() if v not in (None, "", [])}}


# --------------------------------------------------------------------------- describe_data
def describe_data(dataset: str | None = None) -> dict:
    """What can be asked, of which data, over what period, and who owns what."""
    targets = [resolve(dataset)] if dataset else list(REGISTRY.values())
    described = []
    for d in targets:
        facts = db.query(
            f"SELECT count(*) AS rows, min({d.time_column}) AS first_ts, "
            f"max({d.time_column}) AS last_ts FROM {d.table}",
            role=None,
        )[0]
        owned = db.query(
            f"SELECT {d.owner_key} AS team, count(*) AS n FROM {d.table} "
            f"GROUP BY 1 ORDER BY 2 DESC",
            role=None,
        )
        described.append(
            {
                "dataset": d.key,
                "label": d.label,
                "rows": facts["rows"],
                "time_range": [str(facts["first_ts"]), str(facts["last_ts"])],
                "searchable_via": d.index,
                "aggregate_on": d.table,
                "group_by_options": d.group_names,
                "owners": {r["team"]: r["n"] for r in owned},
                "scope_note": d.scope_note,
            }
        )
    env = Envelope(
        tool="describe_data",
        dataset=", ".join(d["dataset"] for d in described),
        scope=_scope(targets[0], **({} if len(targets) == 1 else {"all_datasets": True})),
        sql="-- registry + one count/range/ownership query per dataset",
        rows=described,
        total_matches=len(described),
        columns=["dataset", "label", "rows", "time_range", "searchable_via", "aggregate_on",
                 "group_by_options", "owners", "scope_note"],
        notes=[
            "Search runs against the index relation; aggregation runs on the table. "
            "`@@` against the table fails even with an index attached.",
            "Ownership is our own invented mapping (logger > service > component); "
            "unmapped keys stay visible as UNOWNED.",
        ],
    )
    out = env.as_dict()
    out["headline"] = env.headline()
    return out


# --------------------------------------------------------------------------- search_logs
def search_logs(
    dataset: str,
    query: str,
    mode: str = "phrase",
    limit: int = 10,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> dict:
    """Find evidence: matching lines, with the matched terms highlighted."""
    d = resolve(dataset)
    limit = max(1, min(int(limit), 200))
    params: list[Any] = []
    pred, label = _predicate(d, query, mode, params)
    where = [pred, *_filters(d, params, since=since, until=until, level=level, team=team)]

    total = db.scalar(f"SELECT count(*) FROM {d.index} WHERE {' AND '.join(where)}", params)
    rows_sql = (
        f"SELECT {d.id_column} AS id, {d.time_column} AS ts"
        + (f", {d.node_column} AS node" if d.node_column else "")
        + f", {d.level_column} AS level, {d.owner_key} AS team,"
        f" ts_highlight({d.search_column}, ts_offsets({d.search_column})) AS highlight,"
        f" left({d.search_column}, 400) AS content"
        f" FROM {d.index} WHERE {' AND '.join(where)}"
        f" ORDER BY {d.time_column} DESC LIMIT %s"
    )
    rows = db.query(rows_sql, [*params, limit])

    env = Envelope(
        tool="search_logs",
        dataset=d.key,
        scope=_scope(d, query=query, since=since, until=until, level=level, team=team),
        sql=rows_sql,
        params=[*params, limit],
        rows=rows,
        total_matches=total,
        columns=list(rows[0].keys()) if rows else ["id", "ts", "node", "level", "team", "highlight", "content"],
        operator=label,
        notes=[
            f"operator: {label} on {d.index}.{d.search_column} — counts are not comparable across operators",
            "highlights come from ts_offsets/ts_highlight inside the same @@ sub-query",
        ],
    )
    out = env.as_dict()
    out["headline"] = env.headline()
    return out


# --------------------------------------------------------------------------- count_events
def count_events(
    dataset: str,
    group_by: str = "signature",
    query: str | None = None,
    mode: str = "phrase",
    limit: int = 20,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> dict:
    """How many, bucketed. Without a query this is pure aggregation on the table."""
    d = resolve(dataset)
    limit = max(1, min(int(limit), 200))
    bucket = d.group_column(group_by)

    params: list[Any] = []
    clauses = _filters(d, params, since=since, until=until, level=level, team=team)
    source, label = d.table, "plain aggregation (no full-text operator)"
    if query:
        pred, label = _predicate(d, query, mode, params)
        clauses.insert(0, pred)
        source = d.index
    where = f" WHERE {' AND '.join(clauses)}" if clauses else ""

    total = db.scalar(f"SELECT count(*) FROM {source}{where}", params)
    rows_sql = (
        f"SELECT {bucket} AS bucket, count(*) AS n FROM {source}{where}"
        f" GROUP BY 1 ORDER BY 2 DESC LIMIT %s"
    )
    rows = db.query(rows_sql, [*params, limit])

    env = Envelope(
        tool="count_events",
        dataset=d.key,
        scope=_scope(d, grouped_by=group_by, query=query, since=since, until=until, level=level, team=team),
        sql=rows_sql,
        params=[*params, limit],
        rows=rows,
        total_matches=total,
        columns=["bucket", "n"],
        operator=label,
        notes=[
            f"bucketed by {group_by} -> {bucket}",
            "counts are rows, not incidents — pass a query and read the `episodes` tool for that",
        ],
    )
    out = env.as_dict()
    out["headline"] = env.headline()
    return out
