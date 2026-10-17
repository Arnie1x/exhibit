"""The evidence ledger.

Every answer cites an evidence id (``E-AB12CD``, computed in ``envelope.py``). This module stores,
for each id, the statement that produced the number, the parameters bound into it, and a hash of
the rows that came back -- so ``verify_evidence`` can re-run the question and a judge can check a
number instead of trusting it.

Two rules shape it:

* **append-only.** Re-running a question writes a new row rather than overwriting, so the history
  of an answer stays visible;
* **a ledger write must never break a tool.** If the write fails the answer still comes back, with
  a note saying the evidence was not recorded. A demo that dies because its bookkeeping failed is
  worse than one that admits the bookkeeping failed.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from typing import Any, Sequence

from . import db

TABLE = "exhibit_evidence"


def rows_hash(rows: Sequence[dict]) -> str:
    """sha1 of the rows, canonically serialised, **order-independent**.

    Datetimes go through ``isoformat`` and anything else unknown through ``str``, so the same result
    set hashes the same way on every run.

    The rows are sorted before hashing because row order is presentation, not content: a statement
    with ties in its ORDER BY (19,250 incidents, thousands of them one line long) can come back in a
    different sequence between runs, and a hash that moved when only the tie order moved would report
    a MISMATCH every single time. Comparison is about which rows came back, not their sequence.
    """
    payload = sorted(
        json.dumps({k: _scalar(v) for k, v in r.items()}, sort_keys=True, default=str) for r in rows
    )
    return hashlib.sha1("\n".join(payload).encode()).hexdigest()


def _scalar(value: Any) -> Any:
    if isinstance(value, (list, tuple)):
        return [_scalar(v) for v in value]
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def _encode(params: Sequence[Any]) -> str:
    """Type-tagged JSON, so a re-run binds the *same types* the first run did.

    Persisting a datetime as a string and binding the string back would compare differently on a
    timestamp column; the tag keeps ``datetime`` a ``datetime``.
    """
    out: list[Any] = []
    for item in params:
        if isinstance(item, datetime):
            out.append({"t": "ts", "v": item.isoformat()})
        elif isinstance(item, (list, tuple)):
            out.append({"t": "list", "v": [str(v) for v in item]})
        else:
            out.append(item)
    return json.dumps(out)


def _decode(text: str | None) -> list[Any]:
    out: list[Any] = []
    for item in json.loads(text or "[]"):
        if isinstance(item, dict) and item.get("t") == "ts":
            out.append(datetime.fromisoformat(item["v"]))
        elif isinstance(item, dict) and item.get("t") == "list":
            out.append(list(item["v"]))
        else:
            out.append(item)
    return out


def record(env: dict[str, Any], sql: str, params: Sequence[Any],
           rows: Sequence[dict] | None = None) -> str:
    """Store one answer's evidence. Returns the evidence id.

    ``rows`` is what the *statement* returns, which is not always what the envelope shows: a tool
    that fetches everything and then pages in Python would otherwise record the hash of the page
    while `verify` re-ran the whole statement, and every check would report a false MISMATCH. The
    ledger's contract is "re-run this statement and you get these rows".
    """
    statement_rows = list(rows) if rows is not None else list(env.get("rows") or [])
    db.execute(
        f"INSERT INTO {TABLE} (evidence_id, created_at, tool, persona, role, dataset, scope,"
        " sql_text, params_json, rows_hash, row_count) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s,"
        " %s, %s)",
        [
            env["evidence_id"],
            datetime.now(timezone.utc).replace(tzinfo=None),
            env["tool"],
            env["persona"],
            env["role"],
            env["dataset"],
            json.dumps(env.get("scope") or {}, sort_keys=True, default=str),
            sql,
            _encode(params),
            rows_hash(statement_rows),
            len(statement_rows),
        ],
    )
    return env["evidence_id"]


def latest(evidence_id: str) -> dict | None:
    rows = db.query(
        f"SELECT * FROM {TABLE} WHERE evidence_id = %s ORDER BY created_at DESC LIMIT 1",
        [evidence_id],
    )
    return rows[0] if rows else None


def entries(limit: int = 20) -> list[dict]:
    return db.query(
        f"SELECT evidence_id, created_at, tool, persona, role, dataset, row_count FROM {TABLE}"
        " ORDER BY created_at DESC LIMIT %s",
        [max(1, min(int(limit), 200))],
    )


def count() -> int:
    return int(db.scalar(f"SELECT count(*) FROM {TABLE}") or 0)


def verify(evidence_id: str, sample: int = 3) -> dict[str, Any]:
    """Re-run the stored statement and compare the result to what was recorded.

    The comparison is on the row hash *and* the row count: a hash alone would hide a query that
    now returns a different number of rows of the same shape, and a count alone would miss edited
    values. A mismatch is not a bug in the ledger -- it means the corpus or the definition moved
    since the answer was given, which is exactly what a reader wants to know.
    """
    row = latest(evidence_id.strip().upper())
    if row is None:
        raise KeyError(
            f"no evidence stored for {evidence_id!r}; the ledger holds what this server produced, "
            f"and holds it from the moment sql/55_evidence.sql was applied"
        )

    params = _decode(row["params_json"])
    now = db.query(row["sql_text"], params, role=row["role"])
    stored_hash, now_hash = row["rows_hash"], rows_hash(now)
    match = stored_hash == now_hash and int(row["row_count"]) == len(now)

    return {
        "evidence_id": row["evidence_id"],
        "tool": row["tool"],
        "persona": row["persona"],
        "role": row["role"],
        "dataset": row["dataset"],
        "scope": json.loads(row["scope"] or "{}"),
        "recorded_at": str(row["created_at"]),
        "rows_recorded": int(row["row_count"]),
        "rows_now": len(now),
        "hash_recorded": stored_hash,
        "hash_now": now_hash,
        "match": match,
        "verdict": (
            "MATCH - re-running the stored statement returns the same rows"
            if match
            else "MISMATCH - the corpus or the definition changed since this answer was given"
        ),
        "sql": row["sql_text"],
        "params_recalled": [str(p) for p in params],
        "rows_now_sample": now[: max(1, int(sample))],
    }
