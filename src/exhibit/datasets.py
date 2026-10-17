"""The dataset registry: the only place that knows physical names.

Logical name -> table (aggregation) + index relation (search). Pattern B of the capability
matrix: `@@` runs against the index relation and *only* against it, because a plain derived
table refuses the operator even with an index attached to it.

Tools reach columns through this module and never hard-code a name, which is what makes a
schema change a one-file edit instead of a hunt through twenty queries.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Dataset:
    key: str
    label: str
    table: str                      # aggregation target (plain derived table)
    index: str                      # search target (inverted-indexed relation)
    search_column: str              # the tokenised column
    time_column: str
    id_column: str
    level_column: str
    signature_column: str = ""      # pre-masked value already stored in the table
    node_column: str = ""
    groups: dict[str, str] = field(default_factory=dict)
    owner_key: str = "team"
    scope_note: str = ""

    def group_column(self, logical: str) -> str:
        try:
            return self.groups[logical]
        except KeyError:
            raise KeyError(
                f"unknown group {logical!r} for {self.key}; "
                f"available: {', '.join(sorted(self.groups))}"
            ) from None

    @property
    def group_names(self) -> list[str]:
        return sorted(self.groups)


BGL = Dataset(
    key="bgl",
    label="BGL — Blue Gene/L supercomputer logs (2005-06-03 to 2006-01-04), Loghub record 8196385",
    table="bgl_ev",
    index="bgl_idx",
    search_column="content",
    time_column="ts",
    id_column="id",
    level_column="level",
    signature_column="alert_category",
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
    },
    scope_note=(
        "4,747,963 rows; 348,460 alert lines. The `-` label does NOT mean healthy: 84,253 lines "
        "labelled normal contain an ASSERT fault, so rank problems by message signature."
    ),
)

OPENSTACK = Dataset(
    key="openstack",
    label="OpenStack — nova logs (2017-05-14 to 2017-05-17), Loghub record 8196385",
    table="os_ev",
    index="os_idx",
    search_column="content",
    time_column="ts",
    id_column="id",
    level_column="level",
    signature_column="logger",
    node_column="instance_id",
    groups={
        "service": "service",
        "logger": "logger",
        "level": "level",
        "team": "team",
        "endpoint": "endpoint",
        "instance": "instance_id",
        "status": "status",
    },
    scope_note=(
        "207,812 rows. The whole error surface is one imagecache bug repeated 8 times; the only "
        "CRITICAL lines in the corpus are 2 keystonemiddleware auth failures."
    ),
)

REGISTRY: dict[str, Dataset] = {d.key: d for d in (BGL, OPENSTACK)}


def resolve(key: str | None) -> Dataset:
    if not key:
        raise KeyError(f"a dataset is required; available: {', '.join(sorted(REGISTRY))}")
    try:
        return REGISTRY[key.strip().lower()]
    except KeyError:
        raise KeyError(
            f"unknown dataset {key!r}; available: {', '.join(sorted(REGISTRY))}"
        ) from None


def catalogue() -> str:
    return ", ".join(sorted(REGISTRY))
