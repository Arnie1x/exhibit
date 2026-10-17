"""The registry: logical name -> physical relation, **per persona**.

Two axes, and only this module knows either of them:

* **dataset** — which corpus (`bgl`, `openstack`, or the cross-dataset `corpus` rollup);
* **persona** — who is asking (`engineer`, `lead`, `manager`), which decides *what that role may
  read at all*.

The personas are real database roles (`exhibit_engineer`, `exhibit_lead`, `exhibit_manager`), not a
prompt convention: every tool runs under ``SET ROLE``, so a lead cannot read log text because the
database refuses it, not because a system prompt asked nicely. That is why the relations live here
rather than in the tools.

Two shapes of relation, and the difference is not cosmetic:

* **raw** (engineer) — one row per log line; "how many" is ``count(*)``; full-text search works.
* **aggregated** (lead, manager) — one row per bucket with a pre-computed measure; "how many" is
  ``SUM(measure)``, and the counts of distinct things (`nodes`, `instances`, `requests`) must
  **never** be summed across buckets. Full-text search is not available at all: a search on an index
  relation is privilege-checked against the *base table*, which these roles have no grant on.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class PersonaView:
    """What one persona may read from one dataset."""

    relation: str
    groups: dict[str, str] = field(default_factory=dict)
    default_group: str = ""
    measure: str | None = None          # None -> raw rows (count(*)); else SUM(measure)
    search: str | None = None           # searchable relation, by name; None -> not permitted
    search_column: str = "content"
    id_column: str = ""
    time_column: str = "ts"
    level_column: str = "level"
    node_column: str = ""
    distinct_columns: tuple[str, ...] = ()   # never SUM these across buckets
    notes: str = ""

    @property
    def is_raw(self) -> bool:
        return self.measure is None

    @property
    def can_search(self) -> bool:
        return self.search is not None

    def group_column(self, logical: str) -> str:
        try:
            return self.groups[logical]
        except KeyError:
            raise KeyError(
                f"cannot group by {logical!r} here; available: {', '.join(sorted(self.groups))}"
            ) from None

    @property
    def group_names(self) -> list[str]:
        return sorted(self.groups)


@dataclass(frozen=True)
class Persona:
    key: str
    role: str                    # the database role every query runs under
    label: str
    question: str                # the question this persona actually asks
    views: dict[str, PersonaView] = field(default_factory=dict)
    notes: str = ""

    def view(self, dataset_key: str) -> PersonaView:
        try:
            return self.views[dataset_key]
        except KeyError:
            available = ", ".join(sorted(self.views))
            raise KeyError(
                f"{self.key} cannot read {dataset_key!r}; available to this role: {available}"
            ) from None

    @property
    def datasets(self) -> list[str]:
        return sorted(self.views)


@dataclass(frozen=True)
class Dataset:
    key: str
    label: str
    scope_note: str = ""


# --------------------------------------------------------------------------- datasets
BGL = Dataset(
    key="bgl",
    label="BGL — Blue Gene/L supercomputer logs (2005-06-03 to 2006-01-04), Loghub record 8196385",
    scope_note=(
        "4,747,963 rows; 348,460 alert lines. The `-` label does NOT mean healthy: 84,253 lines "
        "labelled normal contain an ASSERT fault. Rank problems by message signature, never by line "
        "volume: one node produced 152,183 lines in 6h21m while a fleet-wide event produced 49,154 "
        "lines across 22,529 nodes."
    ),
)
OPENSTACK = Dataset(
    key="openstack",
    label="OpenStack — nova logs (2017-05-14 to 2017-05-17), Loghub record 8196385",
    scope_note=(
        "207,812 rows. The whole error surface is one imagecache bug recorded 8 times, plus 3,059 "
        "warnings from the same cause. The 4 injected anomalies are visible only through lifecycle "
        "durations, never through levels or latency."
    ),
)
CORPUS = Dataset(
    key="corpus",
    label="Both corpora rolled up by day — manager only",
    scope_note="Per-day totals across BGL and OpenStack: the cross-dataset view a manager needs.",
)

DATASETS: dict[str, Dataset] = {d.key: d for d in (BGL, OPENSTACK, CORPUS)}


# --------------------------------------------------------------------------- personas
ENGINEER = Persona(
    key="engineer",
    role="exhibit_engineer",
    label="Engineer",
    question="what is broken, on which machine, and what does the log line actually say",
    notes="Raw lines and full-text search. The only role that can read log text.",
    views={
        "bgl": PersonaView(
            relation="bgl_ev",
            search="bgl_idx",
            search_column="content",
            id_column="id",
            time_column="ts",
            level_column="level",
            node_column="node",
            groups={
                "signature": "alert_category",
                "component": "component",
                "level": "level",
                "team": "team",
                "node": "node",
                "node_kind": "node_kind",
                "rack": "rack",
                "midplane": "midplane",
                "is_alert": "is_alert",
            },
            default_group="signature",
            notes="Raw table plus the index relation by name — `@@` never runs against the table.",
        ),
        "openstack": PersonaView(
            relation="os_ev",
            search="os_idx",
            search_column="content",
            id_column="id",
            time_column="ts",
            level_column="level",
            node_column="instance_id",
            groups={
                "signature": "logger",
                "logger": "logger",
                "service": "service",
                "level": "level",
                "team": "team",
                "endpoint": "endpoint",
                "instance": "instance_id",
                "status": "status",
            },
            default_group="service",
        ),
    },
)

LEAD = Persona(
    key="lead",
    role="exhibit_lead",
    label="Team lead",
    question="which team's work is this, how is it trending, and is it getting better",
    notes=(
        "Pre-aggregated per day/hour. NO log text and NO full-text search: the index relation is "
        "privilege-checked against the base table, which this role has no grant on. `nodes`, "
        "`instances` and `requests` are distinct per bucket — never sum them."
    ),
    views={
        "bgl": PersonaView(
            relation="lead_bgl_daily",
            measure="lines",
            time_column="day",
            level_column="level",
            groups={
                "day": "day",
                "team": "team",
                "component": "component",
                "level": "level",
                "signature": "signature",
                "signature_id": "signature_id",
                "alert_category": "alert_category",
                "is_alert": "is_alert",
            },
            default_group="component",
            distinct_columns=("nodes", "midplanes"),
            notes="One row per day x team x component x level x signature.",
        ),
        "openstack": PersonaView(
            relation="lead_os_hourly",
            measure="lines",
            time_column="hour",
            level_column="level",
            groups={
                "hour": "hour",
                "team": "team",
                "service": "service",
                "logger": "logger",
                "level": "level",
                "signature": "signature",
                "signature_id": "signature_id",
            },
            default_group="service",
            distinct_columns=("instances", "requests", "http_errors"),
            notes="One row per hour x team x service x logger x level x signature.",
        ),
    },
)

MANAGER = Persona(
    key="manager",
    role="exhibit_manager",
    label="Manager",
    question="what should we fix first, and how do I know I am not being told a story",
    notes=(
        "Risk factors only: blast radius, persistence and worst level per problem. No log text, no "
        "per-line relation, no hostnames or instance IDs. A problem is named by its signature, "
        "component and owning team — never by log text."
    ),
    views={
        "bgl": PersonaView(
            relation="mgr_bgl_risk",
            measure="alert_lines",
            time_column="first_seen",
            level_column="worst_level",
            groups={
                "signature_id": "signature_id",
                "alert_category": "alert_category",
                "component": "component",
                "team": "team",
                "worst_level": "worst_level",
            },
            default_group="team",
            distinct_columns=("nodes_affected", "midplanes_affected", "active_days", "episodes_5min"),
            notes="One row per signature; `episodes_5min` is the incident count at a 5-minute gap.",
        ),
        "openstack": PersonaView(
            relation="mgr_os_risk",
            measure="lines",
            time_column="first_seen",
            level_column="worst_level",
            groups={
                "problem": "problem",
                "service": "service",
                "team": "team",
                "worst_level": "worst_level",
            },
            default_group="problem",
            distinct_columns=("records", "tracebacks", "incidents_5min", "requests_affected"),
            notes="One row per problem, above INFO only.",
        ),
        "corpus": PersonaView(
            relation="mgr_rollup_daily",
            measure="lines",
            time_column="day",
            level_column="level",
            groups={
                "dataset": "dataset",
                "day": "day",
                "team": "team",
                "component": "component",
                "category": "category",
                "level": "level",
            },
            default_group="dataset",
            notes="Both corpora per day — the only cross-dataset view in the project.",
        ),
    },
)

PERSONAS: dict[str, Persona] = {p.key: p for p in (ENGINEER, LEAD, MANAGER)}


def persona(key: str | None) -> Persona:
    key = (key or "engineer").strip().lower()
    try:
        return PERSONAS[key]
    except KeyError:
        raise KeyError(
            f"unknown persona {key!r}; available: {', '.join(sorted(PERSONAS))}"
        ) from None


def dataset(key: str) -> Dataset:
    try:
        return DATASETS[key.strip().lower()]
    except KeyError:
        raise KeyError(
            f"unknown dataset {key!r}; available: {', '.join(sorted(DATASETS))}"
        ) from None


def resolve(persona_key: str | None, dataset_key: str) -> tuple[Persona, Dataset, PersonaView]:
    """Everything a tool needs, or a clear error naming the door that is closed."""
    p = persona(persona_key)
    d = dataset(dataset_key)
    return p, d, p.view(d.key)


def catalogue() -> str:
    return ", ".join(sorted(DATASETS))
