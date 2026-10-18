"""Database access. One place that knows how to reach SereneDB.

Everything in this project speaks through here, so a connection change, a role switch or a
timeout is a one-line edit rather than a hunt. Aggregations and searches are executed with
psycopg's normal server-side binding -- verified working on 26.09.1.3 for both ``@@ %s`` and
``@@ ts_phrase(%s)``. (``PREPARE ... $1`` fails in *psql*; that is a psql limitation, not ours.)
"""
from __future__ import annotations

import os
import threading
from contextlib import contextmanager
from datetime import date, datetime
from typing import Any, Sequence

import psycopg
from mcp.server.mcpserver.exceptions import ToolError
from psycopg.rows import dict_row

HOST = os.getenv("SERENEDB_HOST", "127.0.0.1")
PORT = int(os.getenv("SERENEDB_PORT", "7890"))
USER = os.getenv("SERENEDB_USER", "postgres")
DBNAME = os.getenv("SERENEDB_DB", "postgres")
PASSWORD = os.getenv("SERENEDB_PASSWORD") or None
# Client-side per-statement deadline in seconds (0 disables). See query().
TIMEOUT_S = float(os.getenv("EXHIBIT_QUERY_TIMEOUT", "30"))


def default_persona() -> str:
    """Which persona the tools act as when the caller does not name one.

    EXHIBIT_ROLE holds a persona *key* (`engineer`), not a database role name -- `datasets.py` maps
    it to `exhibit_engineer`. Keeping the two names apart matters: `SET ROLE engineer` fails,
    because no such role exists.
    """
    return (os.getenv("EXHIBIT_PERSONA") or os.getenv("EXHIBIT_ROLE") or "engineer").strip().lower()


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
    """A short-lived connection, optionally under a database role.

    ``role`` must be a **database role name** (`exhibit_lead`). It is applied with SET ROLE, so the
    engine -- not this code -- decides what the statement may read. Passing None means "no role":
    the connection's own identity, used only for setup.
    """
    with psycopg.connect(dsn(), row_factory=dict_row) as conn:
        if role:
            conn.execute(f"SET ROLE {role}")
        yield conn


class QueryTimeout(RuntimeError):
    """The client-side deadline fired."""


def _bindable(value: Any) -> Any:
    """A value the engine accepts as a plain text parameter.

    SereneDB rejects a Python ``datetime`` object in a statement that also carries a tsquery
    operator (``InvalidParameterValue: Invalid unicode (byte sequence mismatch)``), and phrases
    a string literal meeting interval arithmetic as a bogus "current transaction is aborted".
    Datetimes therefore travel as ISO text AND every datetime placeholder carries an explicit
    ``::timestamp`` cast -- tools._filters, analytics._episodes_stored, analytics.nearby_events,
    analytics.trend (days=), analytics.what_changed. A new datetime bind site needs the cast too,
    or the statement fails this engine's way.
    """
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, list):
        return [_bindable(v) for v in value]
    return value


def query(
    sql: str,
    params: Sequence[Any] | None = None,
    role: str | None = None,
    timeout: float | None = None,
) -> list[dict]:
    """Run a statement under a client-side deadline.

    `SET statement_timeout` is accepted and NOT enforced by this engine (probed 17 Oct), so the
    deadline has to live here: a timer cancels the running statement and we raise QueryTimeout
    rather than letting a bad query hang a demo.

    One retry on ``InFailedSqlTransaction``: this engine phrases some statement-level failures as
    "current transaction is aborted" (probed: a string literal in interval arithmetic), and a
    genuinely transient aborted session recovers on a fresh connection. Everything here is
    read-only, so retrying once is safe; a real error fails identically and still surfaces.
    """
    budget = TIMEOUT_S if timeout is None else timeout
    if params:
        params = [_bindable(p) for p in params]
    try:
        return _query_once(sql, params, role, budget)
    except psycopg.errors.InFailedSqlTransaction:
        try:
            return _query_once(sql, params, role, budget)
        except psycopg.errors.InFailedSqlTransaction as exc:
            raise ToolError(
                "the engine left a session in an aborted state and the retry hit another; "
                "try the call once more"
            ) from exc


def _query_once(sql: str, params: Sequence[Any] | None, role: str | None,
                budget: float) -> list[dict]:
    with connect(role=role) as conn:
        timer = None
        if budget and budget > 0:
            timer = threading.Timer(budget, conn.cancel)
            timer.daemon = True
            timer.start()
        try:
            cur = conn.execute(sql, params)
            return [dict(r) for r in cur.fetchall()]
        except psycopg.errors.QueryCanceled as exc:
            raise QueryTimeout(
                f"query exceeded {budget:g}s and was cancelled client-side "
                f"(the engine does not enforce statement_timeout)"
            ) from exc
        except psycopg.errors.InvalidParameterValue as exc:
            raise ToolError(
                f"the engine rejected a literal in this statement ({exc}); "
                "retry with plainer terms (plain ASCII text)"
            ) from exc
        finally:
            if timer is not None:
                timer.cancel()


def execute(sql: str, params: Sequence[Any] | None = None, role: str | None = None,
            timeout: float | None = None) -> None:
    """Run a statement that returns no rows (INSERT, DDL).

    Separate from ``query`` on purpose: ``query`` calls ``fetchall``, and on this engine that fails
    for a statement with no result set -- an INSERT raised "the last operation didn't produce a
    result", which a broad except in the ledger swallowed into a note. Writes go through here so a
    failed write is visible.
    """
    budget = TIMEOUT_S if timeout is None else timeout
    with connect(role=role) as conn:
        timer = None
        if budget and budget > 0:
            timer = threading.Timer(budget, conn.cancel)
            timer.daemon = True
            timer.start()
        try:
            conn.execute(sql, params)
        except psycopg.errors.QueryCanceled as exc:
            raise QueryTimeout(f"statement exceeded {budget:g}s and was cancelled") from exc
        finally:
            if timer is not None:
                timer.cancel()


def scalar(sql: str, params: Sequence[Any] | None = None, role: str | None = None):
    rows = query(sql, params, role=role)
    return next(iter(rows[0].values())) if rows else None


def ping() -> str:
    return str(scalar("SELECT version()"))
