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
            # bgl_sig, not bgl_ev: it is the same rows with the masked signature added, and the
            # engineer is the role that gets to see it. bgl_ev has no `signature` column at all --
            # its `alert_category` is the LABEL, which is a different and coarser thing (84,253
            # ASSERT lines carry the label '-'), so grouping by it and calling it a signature is
            # the trap the whole project is about.
            relation="bgl_sig",
            search="bgl_idx",
            search_column="content",
            id_column="id",
            time_column="ts",
            level_column="level",
            node_column="node",
            groups={
                "signature": "signature",
                "category": "alert_category",
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
            relation="os_sig",       # os_ev's "signature" was the logger; os_sig carries the masked one
            search="os_idx",
            search_column="content",
            id_column="id",
            time_column="ts",
            level_column="level",
            node_column="instance_id",
            groups={
                "signature": "signature",
                "problem": "problem",
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


# =========================================================================== stage 3 specs
# Three more per-(persona, dataset) facts live here, so the tools stay free of identifiers and the
# *shape* of a persona's evidence is declared in one place. The split they encode is the one the
# engine forces on us:
#
# * the engineer holds a grant on the base relation (`bgl_sig` / `os_sig`), so episodes can be
#   **computed** at any gap with the LAG pattern -- the gap is a real parameter there;
# * the lead and manager hold no such grant; they read relations where the 5-minute grouping is
#   already baked in, so their episode count is **precomputed** and the tool must say so rather
#   than pretend it can vary the gap. That is a property of the data they are allowed to see.


@dataclass(frozen=True)
class EpisodeSource:
    """How one persona gets episodes for one dataset."""

    kind: str                            # "computed" | "precomputed"
    relation: str                        # computed: the base sig relation; precomputed: the view
    partitions: dict[str, tuple[str, ...]] = field(default_factory=dict)   # coalescing key options
    order: tuple[str, ...] = ("ts",)
    filter_sql: str = ""
    count_column: str = ""               # precomputed: the column holding the count
    gap_minutes: int | None = None       # precomputed: the gap baked into that relation
    display: tuple[str, ...] = ()        # carried alongside the coalescing key
    nodes: str = "count(DISTINCT node)"  # computed path: the blast-radius expression
    nodes_column: str = "nodes"          # stored path: the column holding it
    node_source: str = "node"            # computed path: the raw column that expression reads
    time_column: str = ""                # precomputed relations only: what `since`/`until` filter
    key_column: str = ""                 # the column holding the signature text, for `signature=`
    note: str = ""

    @property
    def default_partition(self) -> str:
        return next(iter(self.partitions)) if self.partitions else ""


@dataclass(frozen=True)
class SignatureRank:
    """Where one persona's signature ranking comes from, and what the three numbers mean there."""

    relation: str
    key: str                             # the column that names the signature
    grain: tuple[str, ...] = ()          # how rows are grouped; defaults to (key,)
    extra: tuple[str, ...] = ()          # columns carried alongside (team, component, ...)
    node_source: str = ""                # computed path: raw column the node expression reads
    lines: str = "count(*)"
    episodes: str = ""
    nodes: str = ""                      # blast radius
    filter_sql: str = ""
    fixed_gap: int | None = None
    note: str = ""
    node_label: str = "nodes"      # what the blast-radius column actually counts in this relation
    nodes_unmeasurable: str = ""   # set when the corpus cannot support a blast-radius ranking at all


EPISODES: dict[tuple[str, str], EpisodeSource] = {
    ("engineer", "bgl"): EpisodeSource(
        kind="computed",
        relation="bgl_sig",
        partitions={"failure_domain": ("signature", "midplane"), "signature": ("signature",)},
        order=("ts",),
        filter_sql="is_alert",
        key_column="signature",
        display=("signature", "alert_category", "component"),
        note="alert lines coalesced per signature x midplane; pass coalesce_by='signature' to drop "
             "the failure domain (19,250 becomes 1,377 at a 5-minute gap)",
    ),
    ("engineer", "openstack"): EpisodeSource(
        kind="computed",
        relation="os_sig",
        partitions={"problem": ("problem",)},
        order=("ts", "id"),
        filter_sql="level <> 'INFO'",
        display=("service",),
        nodes="count(DISTINCT nullif(instance_id, 'NONE'))",
        node_source="instance_id",
        key_column="problem",
        note="lines above INFO coalesced per problem",
    ),
    ("lead", "bgl"): EpisodeSource(
        kind="precomputed", relation="bgl_incident", gap_minutes=5,
        partitions={"failure_domain": ("signature", "midplane")},
        display=("component", "team"), nodes_column="nodes", time_column="started",
        key_column="signature",
        note="one row per incident at the view's fixed 5-minute gap; the lead has no grant on "
             "bgl_sig, so the gap cannot be varied for this role",
    ),
    ("lead", "openstack"): EpisodeSource(
        kind="precomputed", relation="os_incident", gap_minutes=5,
        partitions={"problem": ("problem",)},
        display=("service", "team"), nodes_column="instances", time_column="started",
        key_column="problem",
        note="one row per incident at the view's fixed 5-minute gap",
    ),
    ("manager", "bgl"): EpisodeSource(
        kind="precomputed", relation="mgr_bgl_risk", count_column="episodes_5min", gap_minutes=5,
        partitions={"signature_id": ("signature_id",)},
        display=("component", "team"), nodes="max(nodes_affected)",
        note="precomputed per signature at a fixed 5-minute gap",
    ),
    ("manager", "openstack"): EpisodeSource(
        kind="precomputed", relation="mgr_os_risk", count_column="incidents_5min", gap_minutes=5,
        partitions={"problem": ("problem",)},
        display=("service", "team"), nodes="max(requests_affected)",
        note="precomputed per problem at a fixed 5-minute gap",
    ),
}

RANK: dict[tuple[str, str], SignatureRank] = {
    ("engineer", "bgl"): SignatureRank(
        relation="bgl_sig", key="signature",
        grain=("signature", "midplane"),
        extra=("alert_category", "component", "team"),
        node_source="node", lines="count(*)", nodes="count(DISTINCT node)",
        filter_sql="is_alert",
        note="grain = signature x midplane, the same grain an incident is coalesced at, so the "
             "episode count is counted on the key it was built from; nodes = distinct machines",
    ),
    ("engineer", "openstack"): SignatureRank(
        relation="os_sig", key="problem", grain=("problem",), extra=("logger", "service", "team"),
        node_source="instance_id",
        lines="count(*)", nodes="count(DISTINCT nullif(instance_id, 'NONE'))",
        filter_sql="level <> 'INFO'",
        note="episodes computed per problem; nodes = distinct instances",
        nodes_unmeasurable=(
            "the corpus attaches an instance id to normal-traffic lines (51,553 of 207,812) and to "
            "none of the lines above INFO that this ranking covers -- 0 of the 68 problem-incidents "
            "carry one -- so ranking by blast radius here would rank 0 against 0. The blast radius "
            "of an OpenStack problem is the service behind it: use by='lines' or by='episodes' and "
            "read the `service` column"
        ),
    ),
    ("lead", "bgl"): SignatureRank(
        relation="bgl_incident", key="signature", grain=("signature",), extra=("team", "component"),
        lines="sum(lines)", episodes="count(*)", nodes="max(nodes)", fixed_gap=5,
        note="lines summed across incidents, episodes counted, nodes as the PEAK blast radius -- "
             "never summed, they are distinct per incident",
    ),
    ("lead", "openstack"): SignatureRank(
        relation="os_incident", key="problem", grain=("problem",), extra=("team", "service"),
        lines="sum(lines)", episodes="count(*)", nodes="max(instances)", fixed_gap=5,
        note="nodes = peak instances per incident",
        nodes_unmeasurable=(
            "os_incident carries 0 instances for all 68 incidents: the corpus's error lines never "
            "identify an instance, so a blast-radius ranking would rank 0 against 0. Rank by "
            "by='lines' or by='episodes' and read the `service` column"
        ),
    ),
    ("manager", "bgl"): SignatureRank(
        relation="mgr_bgl_risk", key="signature_id",
        grain=("signature_id", "component", "team"), extra=("alert_category",),
        lines="sum(alert_lines)", episodes="sum(episodes_5min)", nodes="max(nodes_affected)",
        fixed_gap=5,
        note="a problem is named by signature_id + component + team; no log text",
    ),
    ("manager", "openstack"): SignatureRank(
        relation="mgr_os_risk", key="problem", grain=("problem",), extra=("team", "service"),
        lines="sum(lines)", episodes="sum(incidents_5min)", nodes="max(requests_affected)",
        fixed_gap=5, note="one row per problem, above INFO only; the blast-radius column counts "
"requests affected, not machines -- the corpus's error lines name no instance",
        node_label="requests_affected",
    ),
}

# Time buckets: `date_bin` needs an origin, and our corpora have two very different epochs, so the
# bucket is aligned to the dataset's own start rather than to 1970.
ORIGIN = {
    "bgl": "TIMESTAMP '2005-06-03 00:00:00'",
    "openstack": "TIMESTAMP '2017-05-14 00:00:00'",
    "corpus": "TIMESTAMP '2005-06-03 00:00:00'",
}
BUCKETS: dict[str, int] = {"hour": 1, "day": 24, "week": 168}   # name -> hours

# What the *index* relation carries, probe-verified: it is NOT the base table's column set.
# `bgl_idx` has no `signature` (that lives on `bgl_sig`) and `os_idx` has no `problem`, so a tool
# that walks lines through the index has to name columns this relation actually has.
INDEX_COLUMNS: dict[str, tuple[str, ...]] = {
    "bgl": ("id", "ts", "alert_category", "node", "midplane", "component", "level", "team"),
    "openstack": ("id", "ts", "instance_id", "service", "logger", "level", "team"),
}
INDEX_GROUP: dict[str, str] = {"bgl": "alert_category", "openstack": "logger"}


def episodes_of(persona_key: str | None, dataset_key: str) -> EpisodeSource:
    p, d, _ = resolve(persona_key, dataset_key)
    try:
        return EPISODES[(p.key, d.key)]
    except KeyError:
        raise KeyError(
            f"no episode source for {p.key} on {d.key}; "
            f"available: {', '.join(f'{a}/{b}' for a, b in sorted(EPISODES))}"
        ) from None


@dataclass(frozen=True)
class DurationSource:
    """OpenStack lifecycle timings: per instance for the hands-on roles, a distribution for the
    manager (whose view deliberately carries no instance ids)."""

    relation: str
    key: str
    phases: tuple[str, ...]
    extra: tuple[str, ...] = ()
    note: str = ""


_INSTANCE_DURATIONS = DurationSource(
    relation="os_instance_durations",
    key="instance_id",
    phases=("spawn_s", "build_s", "image_s", "boot_s", "run_s", "teardown_s", "destroy_s",
            "dealloc_s", "claim_s", "lifetime_s"),
    extra=("lines", "source_file", "team"),
    note="one row per instance, ~25 lines each: an outlier here is a slow server build, not a "
         "noisy one. These four phase columns are the only place the labelled anomalies in "
         "anomaly_labels.txt are visible at all -- they log at INFO and their aggregate latency "
         "is identical to the normal files",
)

DURATIONS: dict[str, DurationSource] = {
    "engineer": _INSTANCE_DURATIONS,
    "lead": _INSTANCE_DURATIONS,
    "manager": DurationSource(
        relation="mgr_os_lifecycle",
        key="file_group",
        phases=("spawn_p50_s", "spawn_p95_s", "spawn_max_s", "image_p50_s", "image_max_s",
                "boot_p50_s", "boot_max_s"),
        extra=("instances", "spawned"),
        note="a distribution per file group, not per instance: the manager's view carries no "
             "instance ids and no per-instance phases",
    ),
}


@dataclass(frozen=True)
class ChangeSource:
    """Where one persona reads a before/after comparison, and at what resolution."""

    relation: str
    time_column: str
    key: str                     # the dimension that changed
    measure: str = "count(*)"
    granularity: str = "hour"    # how window_hours is read: exact | whole days
    filter_sql: str = ""
    note: str = ""


CHANGE: dict[tuple[str, str], ChangeSource] = {
    ("engineer", "bgl"): ChangeSource(
        "bgl_sig", "ts", "signature", filter_sql="is_alert",
        note="hour-exact windows on the parsed relation",
    ),
    ("engineer", "openstack"): ChangeSource(
        "os_sig", "ts", "problem", filter_sql="level <> 'INFO'",
        note="hour-exact windows on the parsed relation",
    ),
    ("lead", "bgl"): ChangeSource(
        "lead_bgl_daily", "day", "signature", measure="sum(lines)", granularity="day",
        note="the lead's BGL view is daily, so the window is read in whole days",
    ),
    ("lead", "openstack"): ChangeSource(
        "lead_os_hourly", "hour", "logger", measure="sum(lines)",
        note="the lead's OpenStack view is hourly, so the window is exact",
    ),
    ("manager", "bgl"): ChangeSource(
        "mgr_rollup_daily", "day", "category", measure="sum(lines)", granularity="day",
        filter_sql="dataset = 'bgl'",
        note="the rollup is daily and grouped by category/team/component, not by signature",
    ),
    ("manager", "openstack"): ChangeSource(
        "mgr_rollup_daily", "day", "category", measure="sum(lines)", granularity="day",
        filter_sql="dataset = 'openstack'",
        note="the rollup is daily and grouped by category, not by signature",
    ),
    ("manager", "corpus"): ChangeSource(
        "mgr_rollup_daily", "day", "category", measure="sum(lines)", granularity="day",
        note="the cross-corpus rollup, daily",
    ),
}


def durations_of(persona_key: str | None) -> DurationSource:
    p = persona(persona_key or "engineer")
    try:
        return DURATIONS[p.key]
    except KeyError:
        raise KeyError(f"no duration source for {p.key}") from None


def change_of(persona_key: str | None, dataset_key: str) -> ChangeSource:
    p, d, _ = resolve(persona_key, dataset_key)
    try:
        return CHANGE[(p.key, d.key)]
    except KeyError:
        raise KeyError(
            f"no change source for {p.key} on {d.key}; "
            f"available: {', '.join(f'{a}/{b}' for a, b in sorted(CHANGE))}"
        ) from None


def rank_of(persona_key: str | None, dataset_key: str) -> SignatureRank:
    p, d, _ = resolve(persona_key, dataset_key)
    try:
        return RANK[(p.key, d.key)]
    except KeyError:
        raise KeyError(
            f"no ranking source for {p.key} on {d.key}; "
            f"available: {', '.join(f'{a}/{b}' for a, b in sorted(RANK))}"
        ) from None
