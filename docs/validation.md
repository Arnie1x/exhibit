# Validation against ground truth

`make validate` (`scripts/validate_ground_truth.py`) scores what our analysis recovered against the
two answer keys that ship with the corpora. It runs **outside the agent**: it is not an MCP tool,
it reads `anomaly_labels.txt` from disk, and that file is never loaded into SereneDB. Every figure
below is computed by SereneDB; the script compares a handful of aggregated rows and exits 1 if any
pinned value moves. Measured 17 Oct on `serenedb/serenedb:26.09.1.3`, identical across three runs.

The two keys are different kinds of thing, and the script treats them differently:

| Key | Where it lives | Can the agent see it? | What we check |
| --- | --- | --- | --- |
| `anomaly_labels.txt` (OpenStack): 4 instance IDs with injected anomalies | `data/loghub/`, read only by this script | **No.** No relation or column holds it; none of the 12 MCP tools reads it (both asserted by the script) | Does the ranking the agent's own `durations` tool returns put the 4 labelled instances on top? |
| BGL label column (41 alert categories plus `-`) | `bgl_ev.alert_category`, `is_alert` | **Yes**, by design: the brief supplies it, the engineer can group by it, and "alert line" is defined from it | Does a signature computed from the message text **alone** reproduce it? Every BGL ranking sits on signatures |

## 1. OpenStack: the labelled anomalies, through the agent's own tool

The script calls `durations(dataset="openstack", persona="lead", by="spawn_s")`, records its
evidence ID, and scores the whole ranking (2,069 instances, ties broken on `instance_id`).

| Expectation | Result |
| --- | --- |
| The agent's top 10 equals the scored top 10, same order | yes (10 of 10) |
| The 4 labelled instances rank, by spawn time, out of 2,069 | **1, 2, 3, 4** (50.72, 41.81, 31.27, 29.46 s) |
| recall@4 / precision@4 | 4/4 and 4/4 |
| Position 5, the first unlabelled instance | `d7d68893`, 26.69 s, also in `openstack_abnormal.log` (the near miss) |
| The image phase alone ranks them | 1, 2, 3, 4 as well (44.454, 34.647, 25.217, 22.444 s): the time is spent creating the image |
| Chance of 4 random instances filling the top 4 | 1 in 761,325,852,001 (`C(2069, 4)`; context, not a significance test) |
| **Negative control: severity filter** | 100 lines from the 4 instances, **0 above INFO** |
| **Negative control: API latency** | abnormal vs normal file: mean 0.2340 vs 0.2341 s, p95 0.3771 vs 0.3826 s (9,416 vs 89,317 calls) |

Within the abnormal file alone (198 instances) they are also positions 1–4. The two places an agent
would look first (error levels and latency percentiles) find nothing; only lifecycle duration does.

## 2. BGL: do text-only signatures carry the expert label?

A signature is the message with UUIDs and digits masked (`sql/30_views.sql`, `bgl_sig`). It never
reads the label. Grouping all 4,747,963 lines by signature gives 29,670 signatures. A line "agrees"
when its label is its signature's majority label. A signature with a tied majority goes to `-` (no
majority, no alarm), so the result does not depend on scan order.

| | Result |
| --- | --- |
| Line agreement with the signature's majority label | **99.9998%** (9 of 4,747,963 lines differ) |
| Signatures carrying more than one label | 4 of 29,670 |

As an alert detector (predict "alert" when the signature's majority label is an alert category),
against the label as truth:

| Detector | TP | FP | FN | Precision | Recall | F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Signature majority is an alert | 348,454 | 3 | 6 | 0.999991 | 0.999983 | 0.999987 |
| Level is FATAL or FAILURE (label-free alternative) | 348,460 | 508,755 | 0 | 0.406502 | 1.000000 | 0.578033 |

The 9 disagreeing lines sit in four signatures, each overwhelmingly one label: `Microloader
Assertion` (1,503 `KERNMICRO`, 1 `-`), `data storage interrupt` (63,491 `KERNSTOR`, 2 `-`),
`program interrupt` (3,662 `-`, 5 `KERNPROG`) and `ciodb exited normally with exit code {n}` (1 `-`,
1 `MASNORM`). That is label noise, not new faults.

What this establishes: ranking BGL by signature loses nothing the expert label knew, and the same
method works on logs that carry no labels, where 59% of a severity filter's alarms would be false.
What it does **not** establish: that the label is complete. The 84,253 `idoproxydb hit ASSERT
condition` lines are consistently labelled `-`, so signature and label agree that they are "normal",
and only the message text says they are faults (`docs/data-notes.md`).

## Reproduce

```bash
make validate          # 13/13 expectations hold; exit 0
```

The script imports the server's own tool registry and the `durations` tool (`src/exhibit/`). It
connects as the server's login, with the same `SERENEDB_*` environment, and reads the labels from
`--labels PATH` (default `data/loghub/anomaly_labels.txt`). The `durations` evidence ID it prints can
be re-run with `verify_evidence`.
