"""The tools: describe_data, search_logs, count_events — now persona-aware.

Every statement runs under the caller's database role (``SET ROLE``), so scope is enforced by the
engine, not by prose in a system prompt. Two consequences shape this file:

* a request a role may not make is answered with a **refusal envelope** (``refused: true``) rather
  than an exception or, worse, a silently empty result -- the refusal names the role, the door and
  the way round, which is what makes the three personas demonstrable rather than decorative;
* ``count_events`` counts rows on a raw relation and **sums a measure** on an aggregated one, and it
  states which it did -- those two numbers are not the same kind of thing.

Full-text search runs against the index relation named by the persona's view (never the base table,
which refuses ``@@``). Roles without a searchable relation cannot search at all, because the
privilege check on an index relation resolves to the base table they have no grant on.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any

from . import db
from .datasets import Persona, PersonaView, persona as persona_meta
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


def _predicate(view: PersonaView, query: str, mode: str, params: list) -> tuple[str, str]:
    """Return (sql fragment, human name of the operator)."""
    mode = (mode or "phrase").strip().lower()
    if mode not in MODES:
        raise ValueError(f"unknown mode {mode!r}; available: {', '.join(sorted(MODES))}")
    if mode in ("any", "all"):
        params.append([t.strip() for t in query.split(",") if t.strip()])
    else:
        params.append(query)
    fragment, label = MODES[mode]
    return f"{view.search_column} @@ {fragment}", label


def _filters(view: PersonaView, params: list, *, since=None, until=None, level=None, team=None) -> list[str]:
    clauses: list[str] = []
    if (since_dt := _as_dt(since)) is not None:
        clauses.append(f"{view.time_column} >= %s")
        params.append(since_dt)
    if (until_dt := _as_dt(until)) is not None:
        clauses.append(f"{view.time_column} < %s")
        params.append(until_dt)
    if level:
        clauses.append(f"{view.level_column} = %s")
        params.append(level.upper())
    if team:
        clauses.append("team = %s")
        params.append(team.lower())
    return clauses


def _scope(dataset_key: str, **kw) -> dict[str, Any]:
    return {"dataset": dataset_key, **{k: v for k, v in kw.items() if v not in (None, "", [])}}


def _envelope(tool: str, dataset_key: str, p: Persona, sql: str, **kw) -> dict:
    env = Envelope(tool=tool, dataset=dataset_key, sql=sql, persona=p.key, role=p.role, **kw)
    out = env.as_dict()
    out["headline"] = env.headline()
    return out


def _refuse(tool: str, dataset_key: str, p: Persona, reason: str, scope: dict) -> dict:
    """A refusal is an answer: it names the role, the door, and the way round."""
    return _envelope(
        tool,
        dataset_key,
        p,
        "-- refused before any SQL ran",
        scope=scope,
        refused=True,
        notes=[reason, p.notes],
    )


def _asked(persona: str | None) -> Persona:
    return persona_meta(persona or db.default_persona())


def _agg(view: PersonaView) -> str:
    """count(*) on a raw relation; a BIGINT-cast SUM on an aggregated one.

    The cast matters: the aggregate views hold their measure as a wider numeric type, which the
    driver hands back as a string. "4325112" == 4325112 reads as a coincidence to a human and as a
    mismatch to a comparison, so the number arrives as a number.
    """
    return f"cast(sum({view.measure}) as bigint)" if view.measure else "count(*)"


# --------------------------------------------------------------------------- describe_data
def describe_data(persona: str | None = None, dataset: str | None = None) -> dict:
    """What this role can ask, of which data, over what period, grouped how."""
    p = _asked(persona)
    keys = [dataset.strip().lower()] if dataset else p.datasets
    described = []
    for key in keys:
        view = p.views.get(key)
        if view is None:
            continue
        agg = _agg(view)
        facts = db.query(
            f"SELECT {agg} AS total, min({view.time_column}) AS first_ts, "
            f"max({view.time_column}) AS last_ts FROM {view.relation}",
            role=p.role,
        )[0]
        described.append(
            {
                "dataset": key,
                "readable_as": view.relation,
                "shape": "raw lines" if view.is_raw else f"pre-aggregated, measure = {view.measure}",
                "total": facts["total"],
                "time_range": [str(facts["first_ts"]), str(facts["last_ts"])],
                "can_search": view.can_search,
                "searchable_via": view.search or "not permitted for this role",
                "group_by_options": view.group_names,
                "default_group": view.default_group,
                "never_sum_these": list(view.distinct_columns),
                "notes": view.notes,
            }
        )
    if not described:
        return _refuse(
            "describe_data",
            dataset or "-",
            p,
            f"{p.key} cannot read {dataset!r}; readable: {', '.join(p.datasets)}",
            _scope(dataset or "-"),
        )
    return _envelope(
        "describe_data",
        ", ".join(d["dataset"] for d in described),
        p,
        "-- registry + one total/range query per readable dataset, under this role",
        scope={"persona": p.key, "datasets": [d["dataset"] for d in described]},
        rows=described,
        total_matches=len(described),
        columns=["dataset", "readable_as", "shape", "total", "time_range", "can_search",
                 "group_by_options", "never_sum_these", "notes"],
        notes=[p.question, p.notes],
    )


# --------------------------------------------------------------------------- search_logs
def search_logs(
    dataset: str,
    query: str,
    persona: str | None = None,
    mode: str = "phrase",
    limit: int = 10,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> dict:
    """Find evidence: matching lines with the matched terms highlighted. Engineer only."""
    p = _asked(persona)
    view = p.views.get(dataset.strip().lower())
    scope = _scope(dataset, query=query, mode=mode, since=since, until=until, level=level, team=team)
    if view is None:
        return _refuse(
            "search_logs", dataset, p,
            f"{p.key} cannot read {dataset!r}; readable: {', '.join(p.datasets)}", scope,
        )
    if not view.can_search:
        return _refuse(
            "search_logs", dataset, p,
            f"full-text search is not available to {p.key}: a search on an index relation is "
            f"privilege-checked against the base table, which this role has no grant on. "
            f"{p.key} reads {view.relation} instead — use count_events.", scope,
        )

    limit = max(1, min(int(limit), 200))
    params: list[Any] = []
    pred, label = _predicate(view, query, mode, params)
    where = [pred, *_filters(view, params, since=since, until=until, level=level, team=team)]

    total = db.scalar(
        f"SELECT count(*) FROM {view.search} WHERE {' AND '.join(where)}", params, role=p.role
    )
    rows_sql = (
        f"SELECT {view.id_column} AS id, {view.time_column} AS ts"
        + (f", {view.node_column} AS node" if view.node_column else "")
        + f", {view.level_column} AS level, team,"
        f" ts_highlight({view.search_column}, ts_offsets({view.search_column})) AS highlight,"
        f" left({view.search_column}, 400) AS content"
        f" FROM {view.search} WHERE {' AND '.join(where)}"
        f" ORDER BY {view.time_column} DESC LIMIT %s"
    )
    rows = db.query(rows_sql, [*params, limit], role=p.role)

    return _envelope(
        "search_logs",
        dataset,
        p,
        rows_sql,
        scope=scope,
        params=[*params, limit],
        rows=rows,
        total_matches=total,
        columns=list(rows[0].keys()) if rows else ["id", "ts", "node", "level", "team",
                                                   "highlight", "content"],
        operator=label,
        notes=[
            f"operator: {label} on {view.search}.{view.search_column} — counts are not comparable "
            f"across operators",
            "highlights come from ts_offsets/ts_highlight inside the same @@ sub-query",
            f"read as {p.role}",
        ],
    )


# --------------------------------------------------------------------------- count_events
def count_events(
    dataset: str,
    group_by: str | None = None,
    persona: str | None = None,
    query: str | None = None,
    mode: str = "phrase",
    limit: int = 20,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> dict:
    """How many, bucketed.

    On a raw relation this counts rows; on an aggregated one it sums the view's measure and says so.
    Passing ``query`` needs a searchable relation, so it is engineer-only.
    """
    p = _asked(persona)
    view = p.views.get(dataset.strip().lower())
    scope = _scope(dataset, grouped_by=group_by or "", query=query, since=since, until=until,
                   level=level, team=team)
    if view is None:
        return _refuse(
            "count_events", dataset, p,
            f"{p.key} cannot read {dataset!r}; readable: {', '.join(p.datasets)}", scope,
        )
    if query and not view.can_search:
        return _refuse(
            "count_events", dataset, p,
            f"a full-text predicate is not available to {p.key} (no grant on the base table behind "
            f"the index relation). Bucket {view.relation} by its own columns instead.", scope,
        )

    group_by = (group_by or view.default_group
                or (view.group_names[0] if view.group_names else "")).strip()
    bucket = view.group_column(group_by)
    limit = max(1, min(int(limit), 200))

    params: list[Any] = []
    clauses = _filters(view, params, since=since, until=until, level=level, team=team)
    source, operator = view.relation, "plain aggregation (no full-text operator)"
    if query:
        pred, operator = _predicate(view, query, mode, params)
        clauses.insert(0, pred)
        source = view.search or view.relation
    where = f" WHERE {' AND '.join(clauses)}" if clauses else ""
    agg = _agg(view)

    total = db.scalar(f"SELECT {agg} FROM {source}{where}", params, role=p.role)
    rows_sql = (
        f"SELECT {bucket} AS bucket, {agg} AS n FROM {source}{where}"
        f" GROUP BY 1 ORDER BY 2 DESC LIMIT %s"
    )
    rows = db.query(rows_sql, [*params, limit], role=p.role)

    return _envelope(
        "count_events",
        dataset,
        p,
        rows_sql,
        scope=scope,
        params=[*params, limit],
        rows=rows,
        total_matches=total,
        columns=["bucket", "n"],
        operator=operator,
        measure=view.measure,
        notes=[
            f"bucketed by {group_by} -> {bucket} on {source}",
            "n = count(*) of raw rows" if view.is_raw
            else f"n = sum({view.measure}) of the view's own measure — not a row count",
            *([f"never sum {', '.join(view.distinct_columns)}: distinct per bucket"]
              if view.distinct_columns else []),
            "lines are not incidents — the `episodes` tool answers that and arrives in Stage 3",
            f"read as {p.role}",
        ],
    )
