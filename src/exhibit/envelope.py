"""The result envelope — the single most important interface in the project.

Every tool returns one of these. It carries the rows *and* the provenance: the SQL, the bound
parameters, the scope, the true match total, whether the answer was truncated, and a stable
evidence id. The answer contract and the numeric lint both read this structure, so "show your
work" is automatic rather than a discipline someone has to remember.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from typing import Any, Sequence

from .db import render_sql


@dataclass
class Envelope:
    tool: str
    dataset: str
    scope: dict[str, Any]
    sql: str
    params: Sequence[Any] = field(default_factory=list)
    rows: list[dict] = field(default_factory=list)
    total_matches: int | None = None
    columns: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    operator: str = ""          # which full-text operator produced these numbers

    # ------------------------------------------------------------------ derived
    @property
    def returned(self) -> int:
        return len(self.rows)

    @property
    def truncated(self) -> bool:
        if self.total_matches is None:
            return False
        return self.total_matches > self.returned

    @property
    def evidence_id(self) -> str:
        """Stable id for this query+params pair: same query, same id, across runs."""
        payload = json.dumps(
            {"tool": self.tool, "sql": self.sql, "params": _jsonable(self.params), "scope": self.scope},
            sort_keys=True,
        )
        return "E-" + hashlib.sha1(payload.encode()).hexdigest()[:6].upper()

    def as_dict(self) -> dict[str, Any]:
        return {
            "tool": self.tool,
            "dataset": self.dataset,
            "scope": self.scope,
            "evidence_id": self.evidence_id,
            "total_matches": self.total_matches,
            "returned": self.returned,
            "truncated": self.truncated,
            "operator": self.operator,
            "columns": self.columns,
            "rows": self.rows,
            "query": render_sql(self.sql, self.params),
            "notes": self.notes,
        }

    def headline(self) -> str:
        """One line an agent can quote, with the evidence id attached."""
        n = "?" if self.total_matches is None else f"{self.total_matches:,}"
        scope = ", ".join(f"{k}={v}" for k, v in self.scope.items() if v not in (None, ""))
        trunc = f" (showing {self.returned})" if self.truncated else ""
        return f"[{self.evidence_id}] {self.tool}: {n} matching rows{trunc}" + (f" | {scope}" if scope else "")


def _jsonable(value: Any) -> Any:
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    if isinstance(value, dict):
        return {k: _jsonable(v) for k, v in value.items()}
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value
