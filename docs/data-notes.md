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

**`ts` is US Pacific wall-clock time; `epoch` is UTC** (measured 17 Oct). `epoch − ts` is 25,200 s
(UTC−7, PDT) for 3,669,612 rows up to 2005-10-30 01:18, and 28,800 s (UTC−8, PST) for 1,078,351 rows
from 01:20 on; ±1 s is rounding of the fractional seconds. The hour 01:00–02:00 on 2005-10-30 occurs
twice: 49 rows (11 PDT, 38 PST), **none of them alerts**, so episodes are unaffected. Never compare
`bgl_ev.ts` with a UTC time without converting.

```sql
SELECT (epoch - extract(epoch FROM "timestamp"::timestamp))::BIGINT AS epoch_minus_ts_s, count(*)
FROM read_parquet('/data/loghub/bgl.parquet') GROUP BY 1 ORDER BY 2 DESC;
```

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

**Lines, episodes and the burst** (verified 17 Oct by `sql-verifier` with fresh SQL on the raw
Parquet and on `bgl_ev`; re-run with `tests/golden/headline_numbers.sql`):

| Fact | Value |
|---|---|
| Alert lines (`label <> '-'`) | 348,460 |
| Episodes, 5-minute gap, signature × midplane | 19,250 (100 signatures, 2,657 groups, 129 midplanes incl. `UNKNOWN`) |
| Episodes, 5-minute gap, signature only | 1,377 |
| Ties and boundary | no two alert lines share a `ts`; no gap within 1 ms of 300 s, so `>` and `>=` agree; no alert line carries a UUID |
| The 2005-06-11 burst | **152,183** alert lines, one node `R30-M0-N9-C:J16-U01`, 17:17:44.6 → 23:39:32.9 (6h21m48s), 43.67% of all alert lines; 152,182 `KERNDTLB` + 1 `KERNMC`; no other node alerted that day |
| The old figure 136,209 | the same burst with `ts < 23:00:00` (15,974 lines after 23:00 left out) |
| Fleet days | 2005-06-13: 17,409 lines on 16,644 nodes · 2005-06-14: 49,154 lines on 22,529 nodes |

**Ranking factors per alert signature** (17 Oct, `bgl_signature_stats`, printed by `make demo`;
independent SQL in `tests/golden/stage3_numbers.sql`). Each ranking puts a different problem first:

| Rank by | First | Its numbers | Where the loudest (DTLB) lands |
|---|---|---|---|
| Alert lines | `data TLB error interrupt` (KERNDTLB) | 152,734 lines, 117 incidents (5 min, midplane), 541 nodes, **99.64% from one node** | 1 |
| Incidents, 5 min, signature × midplane | `Lustre mount FAILED : bglio{n} : point /p/gb{n}` (KERNMNTF) | 3,667 incidents, 26,426 lines, 1,024 I/O nodes, at most 8 nodes per incident, 12 active days | 117 incidents |
| Blast radius + persistence (sum of the two dense ranks) | `rts panic! - stopping execution` (KERNRTSP) | 3,394 nodes, 124 active days, 308 incidents, 3,983 lines | 12th (541 nodes, 11 days) |

- **"Across eight nodes" means per incident.** Lustre and the ciod signatures peak at 8 nodes in one
  incident but reach 1,024 nodes on 128 midplanes over the corpus (8 I/O nodes per midplane).
- **Team split** (`ownership_coverage`): compute-platform holds 91.09% of all BGL lines but 81.61% of
  alert lines and 51.70% of incidents; workload-runtime holds 18.32% of alert lines and 48.00% of
  incidents (9,240 of 19,250), almost all of them ciod.
- **Trend** (weekly incidents, 5 min, 32 weeks from Monday 2005-05-30, `regr_slope` with zero weeks
  included): Lustre's 3,667 incidents fall in 3 weeks (peak 1,872) and none in the last 9; the top
  ciod signature's 3,638 incidents all fall in the last 9 weeks (slope +14.806 per week), so ciod is
  the one still active when the data ends. The window matters for one figure: `rts: kernel terminated`
  has 10 incidents in the last 9 weeks, 6 in the last 8.
- **Interpolation matters** for two printed values: abnormal-file latency p99 is 0.5092 and abnormal
  spawn p95 is 21.10 under `quantile_cont` (linear); `quantile_disc` gives 0.5093 and 21.19. State it.
- **Ties**: three nodes have 3 DTLB phrase matches each, and rank sums tie at 17 and 18 in the manager
  order; the demo breaks every tie on the ID (node, `signature_id`, `instance_id`), and no stated
  position depends on the tie-break.
- **Gap sensitivity** (`bgl_episode_sensitivity`): DTLB 132 / 117 / 57 incidents at 1 / 5 / 60 min
  per midplane, 37 / 37 / 16 globally; Lustre 3,677 / 3,667 / 2,085. At node scope DTLB is 553 / 553 /
  545, about one incident per node.

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
mistake the whole project is designed to avoid. Precisely (17 Oct): the 188 ERROR + CRITICAL lines
are **184** traceback lines of the image cache bug **plus 4** token-validation lines (2 ERROR,
2 CRITICAL); the auth problem adds 2 WARNING lines for 6 in all.

**Lines → incidents → records** (`os_problem_incidents`, `sql/30_views.sql`; incident = the same
problem with no gap over 5 minutes; record = lines sharing file, pid, ts, logger and level, so a
traceback is one record; `make smoke` §6b):

| Problem (our label, from logger + level) | Worst | Lines | Incidents | Records | Team (ownership) |
|---|---|---|---|---|---|
| token validation failed (identity server 503) | CRITICAL | 6 | 2 | 6 | identity |
| image cache pass failed (InvalidDiskInfo) | ERROR | 184 | 8 | 8 (= 8 tracebacks of 23 lines) | platform-services |
| power-state sync: instance count mismatch | WARNING | 45 | 45 | 45 | compute-platform |
| vcpu count unavailable (cpu affinity) | WARNING | 12 | 10 | 12 | compute-platform |
| image cache: unknown base file | WARNING | 3,059 | **3** | 3,059 | image-service |

- The two auth incidents are one request each, 3 lines in 2 ms, at 06:25:02 on 05-16 and 06:25:03
  on 05-17, in this order: ERROR `Bad response code while validating token: 503`, WARNING
  `Identity response: <!DOCTYPE HTML …>`, CRITICAL `Unable to validate token`. Log text, including that HTML, is
  untrusted data.
- The 3,059 "unknown base file" warnings are a **persistent condition**, not 3,059 events: they
  never pause for 5 minutes inside a log file, so the 3 incidents are exactly the 3 files (270,
  838 and 1,951 lines). The two splits (93,870 s and 31,871 s) are the gaps between the files, not
  quiet periods: read it as "present in all three files". That they share a cause with the
  traceback is a hypothesis.
- **Ownership trap:** the traceback is the image cache failing, but it is logged by
  `oslo_service.periodic_task`, so logger-first precedence assigns it to `platform-services`,
  while the imagecache warnings go to `image-service`. A lead view by owning team splits one bug
  across two teams.

**Instance lifecycle** (`os_instance_durations`; events matched on the exact masked message):
claim (`Attempting claim` → `Claim successful`), image (`Creating image` → `VM Started`), boot
(`VM Started` → `Instance spawned successfully.`), run (→ `Terminating instance`), teardown
(→ `VM Stopped`), plus nova's own `Took N seconds` for spawn, build, destroy and network release.
2,069 instances; 2,066 spawned. Medians: spawn 19.74 s, image 13.08 s (over 2,065: `b9000564…`
has no `Creating image` line because `openstack_normal1.log` starts mid-lifecycle), boot 6.65 s.
Verified 17 Oct by `sql-verifier` on the raw Parquet and `os_ev`: `tests/golden/w2_numbers.sql`.

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

**Where the time goes** (17 Oct): the extra time is in the **image phase** (`Creating image` →
`VM Started`): 44.454, 34.647, 25.217, 22.444 s against a median of 13.08 s, and ranking by that
phase alone also puts the four at positions 1–4 (position 5: 19.808 s). Boot (6.0–7.2 s against a
median of 6.65 s), run and teardown are ordinary. API latency per file (`os_latency_by_file`,
`quantile_cont`): abnormal 9,416 calls, mean 0.2340 s, p95 0.3771 s; normal files 89,317 calls,
mean 0.2341 s, p95 0.3826 s. The abnormal file holds 198 instances, so its name does not reveal
which four are labelled.

They are used **only** by a validation script that the agent cannot reach. See PLAN.md §9.
