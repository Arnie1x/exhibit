# Corpus notes — BGL and OpenStack as actually parsed

Loghub, Zenodo record 8196385. Raw: `BGL.log` 709 MB, OpenStack 58.6 MB across
`openstack_normal1.log`, `openstack_normal2.log`, `openstack_abnormal.log`.
Parsed by `scripts/parse.py` → `bgl.parquet`, `openstack.parquet`.

**Parity is the contract: BGL 4,747,963 of 4,747,963 lines (zero lost).
OpenStack 207,812 of 207,820 (8 lines unusable).** Any change to the parser must keep that.

---

## BGL has four record shapes

A naive `split(' ')` parser silently drops ~0.7% of the file (34,470 lines). The shapes:

1. **Standard**: `<label> <epoch> <date> <node> <date> <node_repeat> <type> <component> <level> <message>`
2. **RAS anchor**: the ninth field is the literal `RAS` — `RAS <component> <level> <message>`.
3. **NULL anchor**: the same triple with the literal `NULL` — `NULL <component> <level> <message>`. **100,141 lines.** Components seen here: DISCOVERY, HARDWARE, MONITOR, CMCS, SERV_NET.
4. **Empty message / multi-line**: lines with only 9 fields (no message), and entries where the message text precedes the anchor.

The anchor is therefore the `<TYPE> <COMPONENT> <LEVEL>` triple where TYPE ∈ {`RAS`, `NULL`} —
not a fixed field index. That single observation is what took parity from 99.27% to 100%.

Columns emitted: `dataset, label, epoch, date, node, timestamp, node_repeat, log_type, component, level, content`.

## OpenStack

`dataset, origin_file, source, service, timestamp, pid, level, logger, request_id, user_id,
tenant_id, instance_id, status_code, latency_s, is_abnormal_file, message`.

Two parser bugs worth remembering:

- `service` originally came out as the Loghub **filename** (`openstack_normal1.log`). It must be
  derived from the log line, giving real services: `nova-api`, `nova-compute`, `nova-scheduler`.
- The `timestamp` column is **VARCHAR** in the Parquet, in both datasets. It must be cast
  (`::timestamp`) before any time arithmetic. `date_trunc` additionally needs `::timestamptz`.

---

## Measured profile

| | BGL | OpenStack |
|---|---|---|
| Rows | 4,747,963 | 207,812 |
| Span | 2005-06-03 15:42:50 → 2006-01-04 08:00:05 | 2017-05-14 19:39:01 → 2017-05-17 12:02:35 |
| Alert lines (`label <> '-'`) | 348,460 | — |
| Distinct alert categories | 42 (41 + `-`) | — |
| Severity levels | 6 | 4 (INFO/WARNING/ERROR/CRITICAL) |
| Components / services | 10 | 3 services, 12 loggers |
| Distinct node strings | 69,252 | — |

BGL severity distribution: INFO 3,735,823 · FATAL 855,501 · ERROR 112,355 · WARNING 23,357 ·
SEVERE 19,213 · FAILURE 1,714. **There is no `Kill` level in the derived data**, despite it
appearing in some descriptions of the corpus.

## OpenStack in detail

| Signal | Lines | Notes |
|---|---|---|
| `GET /v2/{tenant}/servers/detail` | 67,363 (32%) | One poller. Top-message rankings surface this, not problems |
| `Unknown base file: /var/lib/nova/instances/_base/…` | 3,059 | WARNING, from `nova.virt.libvirt.imagecache` |
| ERROR, `oslo_service.periodic_task` | 184 | `qemu_img_info` → `InvalidDiskInfo`, **8 tracebacks** |
| CRITICAL, `keystonemiddleware.auth_token` | 2 | **The only CRITICAL in the corpus.** Plus 2 ERROR and 2 WARNING |
| HTTP 404s | 3,969 | 4% of calls |
| Rows carrying a parsed `instance_id` | 51,553 | 2,066 spawn lines, 2,066 build lines |

**The eight tracebacks are the honest unit.** Counting 188 error *lines* as 188 problems is the
mistake the whole project is designed to avoid.

## The labelled anomalies

`anomaly_labels.txt` lists four VM instance UUIDs with injected anomalies in
`openstack_abnormal.log`:

```
544fd51c-4edc-4780-baae-ba1d80a0acfc
ae651dff-c7ad-43d6-ac96-bbcd820ccca8
a445709b-6ad0-40ec-8860-bec60b6ca0c2
1643649d-2f42-4303-bfcd-7798baec19f9
```

Each produces 25 lines, **all at INFO level**. Mean and p95 API latency are indistinguishable
between the normal and abnormal files (mean 0.234 s in both; p95 0.383 vs 0.377). They are
**lifecycle-duration outliers** — `os_instance_durations` ranks them at positions **1–4** by
spawn/build duration (50.72 / 41.81 / 31.27 / 29.46 s), with the first unlabelled instance at
position 5 (26.69 s). No level filter or latency percentile recovers them.

They are used **only** by a validation script that the agent cannot reach. See PLAN.md §9.
