"""Database access. One place that knows how to reach SereneDB.

Everything in this project speaks through here, so a connection change, a role switch or a
timeout is a one-line edit rather than a hunt. Aggregations and searches are executed with
psycopg's normal server-side binding -- verified working on 26.09.1.3 for both ``@@ %s`` and
``@@ ts_phrase(%s)``. (``PREPARE ... $1`` fails in *psql*; that is a psql limitation, not ours.)
"""
from __future__ import annotations

import os
from contextlib import contextmanager
from typing import Any, Iterable, Sequence

import psycopg
from psycopg.rows import dict_row

HOST = os.getenv("SERENEDB_HOST", "127.0.0.1")
PORT = int(os.getenv("SERENEDB_PORT", "7890"))
USER = os.getenv("SERENEDB_USER", "postgres")
DBNAME = os.getenv("SERENEDB_DB", "postgres")
PASSWORD = os.getenv("SERENEDB_PASSWORD") or None
# Stage 4: each persona connects as its own database role. Empty = the owner (postgres).
ROLE = os.getenv("EXHIBIT_ROLE", "")


def dsn() -> str:
    parts = [f"host={HOST}", f"port={PORT}", f"user={USER}", f"dbname={DBNAME}"]
    if PASSWORD:
        parts.append(f"password={PASSWORD}")
    parts.append("connect_timeout=10")
    return " ".join(parts)


def render_sql(sql: str, params: Sequence[Any] | None = None) -> str:
    """A readable rendering of the statement for the evidence panel.

    Display only -- never executed. The engine receives bound parameters, this is what a human
    reads next to the answer.
    """
    if not params:
        return " ".join(sql.split())
    out, i = [], 0
    for chunk in sql.split("%s"):
        out.append(chunk)
        if i < len(params):
            out.append(_literal(params[i]))
            i += 1
    return " ".join("".join(out).split())


def _literal(value: Any) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (list, tuple)):
        inner = ", ".join(_literal(v) for v in value)
        return f"ARRAY[{inner}]"
    text = str(value).replace("'", "''")
    return f"'{text}'"


@contextmanager
def connect(role: str | None = None):
    """A short-lived connection. ``role`` issues SET ROLE for persona-scoped work."""
    with psycopg.connect(dsn(), row_factory=dict_row) as conn:
        wanted = role if role is not None else ROLE
        if wanted:
            conn.execute(f"SET ROLE {wanted}")
        yield conn


def query(sql: str, params: Sequence[Any] | None = None, role: str | None = None) -> list[dict]:
    with connect(role=role) as conn:
        cur = conn.execute(sql, params)
        return [dict(r) for r in cur.fetchall()]


def scalar(sql: str, params: Sequence[Any] | None = None, role: str | None = None):
    rows = query(sql, params, role=role)
    return next(iter(rows[0].values())) if rows else None


def ping() -> str:
    return str(scalar("SELECT version()"))
