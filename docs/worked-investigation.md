# Worked investigation: the questions, the queries, the answers

Team **Logging off Early** — SchubKI National AI Hackathon 2026, track 04, SereneDB.

This is the worked investigation the submission asks for: the questions we put to the corpora, the
tool calls and executed SQL behind them, the results, and the answers and recommended actions for
the three roles. Every figure below is printed by a command you can run; nothing here is
transcribed by hand.

## How to reproduce it

```bash
make bootstrap          # load + index both corpora (~20 s)
make demo               # W1 and W2, engineer -> lead -> manager, each step under its role
make check              # the acceptance suite that pins the numbers below
make validate           # the ground-truth score, outside the agent
```

`make demo` runs `sql/90_queries.sql` and prints the tables shown here, in this order. The
nearby-events and time-filtered search blocks in the last section are not part of `make demo`
(they are MCP tool calls); their executed SQL is quoted verbatim so you can paste it into `psql`.

Three conventions hold throughout:

- **Every table is truncated.** `make demo` prints the top rows; the tool envelope carries the true
  total, the operator that produced the counts and a `truncated` flag. Truncation is called out
  where it matters.
- **The persona is a database role.** Every block runs under `SET ROLE exhibit_engineer`,
  `exhibit_lead` or `exhibit_manager`. The role decides what can be read, not the prompt.
- **Averages are not affected by the file split.** Where a figure could be read two ways, both
  readings are given.

## Where each submission requirement is met

| Requirement | Where |
|---|---|
| Search and summary tools the agent selects and calls | `src/exhibit/` — 12 tools, MCP server (`make mcp`, `make mcp-http`) |
| README: clean checkout, dependencies, tool descriptions with inputs and outputs | `README.md` — Quickstart, "Run the agent", "Run the agent" tool table |
| Known limitations | `README.md` §Limitations, `docs/capabilities.md`, the last section here |
| **One worked investigation: questions, tool calls, SQL, results, role answers** | **this document** |
| Uses both BGL and OpenStack | W1 (BGL) and W2 (OpenStack) |
| Full-text search with time filters | §"Full-text search with a time filter" |
| Nearby events | §"Nearby events: what happened either side" |
| Grouped counts | W1 E2/E3, L1/L3, M1/M3; W2 E2, L2, L3, M1 |
| A trend | W1 L4/L4b (weekly incidents, 32 weeks) |
| An aggregation over the whole corpus, not a sample | W1 M1 (348,460 alert lines → 19,250 incidents), L1, L3; W2 M1 |
| Special award: MCP connection + large-dataset results | `README.md` §Live demo endpoint, §Huge data; `bench/README.md` |

---

# W1 (BGL): "Which problem should we fix first?"

## Scope

| dataset | lines | alert lines | first timestamp | last timestamp |
|---|---|---|---|---|
| BGL | 4,747,963 | 348,460 | 2005-06-03 15:42:50.363779 | 2006-01-04 08:00:05.233639 |

214 days. **"Alert lines" means the lines whose BGL label column carries a real category** — the
derived flag `is_alert`, that is `alert_category <> '-'`. It is 348,460 of the 4,747,963 lines;
4,399,503 carry the `-` label and are not alerts. This is deliberately **not** the same thing as
"above INFO", which is 1,012,140 lines — a team filtering on severity alone would report three times
the alert count. OpenStack has no label column, so there "problems above INFO" is used instead, and
the two datasets are never summed. The corpus is the full Loghub BGL log, parsed
to Parquet by `scripts/parse.py` and loaded into `bgl_ev` with an inverted index over the message
text (`bgl_idx`). Filters used below: none unless a block states one; the only time filter in W1 is
the pair of calendar-day windows in E3, which is stated.

## The engineer: what is broken, on which machine, and what the line says

**E1 — the loudest signatures by volume.** Tool: `top_signatures(rank_by="lines")`.

| signature | alert_category | alert_lines | episodes_5min | nodes_affected | top_node_pct |
|---|---|---|---|---|---|
| data TLB error interrupt | KERNDTLB | 152,734 | 117 | 541 | 99.64 |
| data storage interrupt | KERNSTOR | 63,491 | 133 | 22,529 | 0.01 |
| ciod: Error reading message prefix on CioStream socket to {n}.{n | APPSEV | 26,546 | 3,638 | 1,024 | 0.13 |
| Lustre mount FAILED : bglio{n} : point /p/gb{n} | KERNMNTF | 26,426 | 3,667 | 1,024 | 0.16 |
| rts: kernel terminated for reason {n} | KERNTERM | 18,587 | 2,641 | 7,650 | 0.12 |

`top_node_pct` is the share of the signature's alert lines that came from its loudest single node.
For DTLB that is 99.64%.

**E2 — full-text search for the phrase, then the same matches by node.** Tools:
`search_logs(query="data TLB error interrupt", mode="phrase")`, then `count_events(group_by="node")`
with the same query. The executed predicate:

```sql
SELECT id, ts, node, level, team,
       ts_highlight(content, ts_offsets(content)) AS highlight,
       left(content, 300) AS content
FROM bgl_idx
WHERE content @@ ts_phrase('data TLB error interrupt')
ORDER BY ts DESC;
```

`total_matches` = **152,734**. Grouped by node:

| node | lines | first_ts | last_ts | span |
|---|---|---|---|---|
| R30-M0-N9-C:J16-U01 | 152,182 | 2005-06-11 17:17:44.898186 | 2005-06-11 23:39:32.87774 | 06:21:47.979554 |
| R22-M0-N7-C:J04-U01 | 3 | 2005-06-05 04:22:46.993259 | 2005-06-05 07:07:58.954255 | 02:45:11.960996 |
| R22-M0-N7-C:J09-U01 | 3 | 2005-06-05 04:22:46.682254 | 2005-06-05 07:07:58.855068 | 02:45:12.172814 |

**E3 — one node against the fleet.** Tool: `count_events(group_by="node", ...)`, run over two
calendar days chosen because they are the corpus's two extremes.

| event | alert_lines | nodes | first_ts | last_ts |
|---|---|---|---|---|
| single-node burst, 2005-06-11 | 152,183 | 1 | 2005-06-11 17:17:44.605961 | 2005-06-11 23:39:32.87774 |
| fleet event, 2005-06-14 | 49,154 | 22,529 | 2005-06-14 09:05:23.409965 | 2005-06-14 21:54:34.514354 |

Two numbers a careful reader will notice and should: the day holds **152,183** alert lines while the
DTLB phrase matches **152,182** of them. Both are right, and they differ by one line — the burst's
first line is a `machine check interrupt` (category `KERNMC`), not a DTLB line. This is the same
one-line distinction behind the 152,182 / 152,183 pair used elsewhere in our material.

**E4 — the gap is a parameter.** Tool: `episodes(signature="data TLB error interrupt", gap_minutes=1|5|60)`.
The gap is not a constant: it is a decision, so we state it every time.

| signature | alert_lines | episodes_1min | episodes_5min | episodes_60min | episodes_1min_global | episodes_5min_global | episodes_60min_global |
|---|---|---|---|---|---|---|---|
| data TLB error interrupt | 152,734 | 132 | 117 | 57 | 37 | 37 | 16 |

`episodes_*` counts incidents per signature × midplane (a failure domain); `*_global` counts per
signature only. The demo's headline table uses the 5-minute gap.

## The team lead: whose work is it, and is it getting worse

**L1 — ownership.** Tool: `ownership(dataset="bgl")`, from the team map in `data/ownership.csv`
(logger → service → component → team; our construction, 100% coverage, documented in
`README.md` §The ownership table).

| team | matched_on | lines | pct_lines | alert_lines | pct_alert_lines |
|---|---|---|---|---|---|
| compute-platform | component | 4,325,112 | 91.09 | 284,391 | 81.61 |
| workload-runtime | component | 228,536 | 4.81 | 63,845 | 18.32 |
| observability | component | 99,064 | 2.09 | 15 | 0 |
| storage-platform | component | 88,930 | 1.87 | 3 | 0 |
| site-infrastructure | component | 5,148 | 0.11 | 0 | 0 |
| network-fabric | component | 1,173 | 0.02 | 206 | 0.06 |

**L2 — ranked by incidents, not lines.** Tool: `top_signatures(rank_by="episodes", gap_minutes=5)`.

| signature | team | episodes_5min | alert_lines | nodes_affected | peak_nodes_per_episode | active_days |
|---|---|---|---|---|---|---|
| Lustre mount FAILED : bglio{n} : point /p/gb{n} | compute-platform | 3,667 | 26,426 | 1,024 | 8 | 12 |
| ciod: Error reading message prefix on CioStream socket to {n}.{n | workload-runtime | 3,638 | 26,546 | 1,024 | 8 | 35 |
| rts: kernel terminated for reason {n} | compute-platform | 2,641 | 18,587 | 7,650 | 512 | 17 |
| ciod: Error reading message prefix after LOAD_MESSAGE on CioStre | workload-runtime | 2,282 | 15,273 | 1,024 | 8 | 27 |
| ciod: Error reading message prefix after LOGIN_MESSAGE on CioStr | workload-runtime | 1,042 | 5,683 | 1,024 | 8 | 10 |
| rts: kernel terminated for reason {n}rts: bad message header: in | compute-platform | 963 | 3,334 | 1,255 | 31 | 10 |

**L3 — lines against incidents, per team.** Tool: `count_events(group_by="team")`. This is the
whole-corpus aggregation, not a sample.

| team | signatures | alert_lines | pct_alert_lines | episodes_5min | pct_episodes |
|---|---|---|---|---|---|
| compute-platform | 65 | 284,391 | 81.61 | 9,952 | 51.7 |
| workload-runtime | 19 | 63,845 | 18.32 | 9,240 | 48 |
| network-fabric | 10 | 206 | 0.06 | 42 | 0.22 |
| observability | 5 | 15 | 0 | 14 | 0.07 |
| storage-platform | 1 | 3 | 0 | 2 | 0.01 |

**L4 — the trend.** Tool: `trend(bucket="week", gap_minutes=5)`, anchored on the corpus's last week,
never on today. `slope_per_week` is `regr_slope` over every week with zero weeks included.

| signature | weeks | active_weeks | incidents | peak_week_incidents | slope_per_week | last_9_weeks |
|---|---|---|---|---|---|---|
| Lustre mount FAILED : bglio{n} : point /p/gb{n} | 32 | 3 | 3,667 | 1,872 | −2.501 | 0 |
| ciod: Error reading message prefix on CioStream socket to {n}.{n | 32 | 8 | 3,638 | 1,110 | +14.806 | 3,638 |
| rts: kernel terminated for reason {n} | 32 | 9 | 2,641 | 1,707 | −4.094 | 10 |
| ciod: Error reading message prefix after LOAD_MESSAGE on CioStre | 32 | 12 | 2,282 | 541 | +0.137 | 175 |

**L4b — the weekly bars** (week 0 = 2005-05-30, 32 weeks in all; active weeks only):

| signature | week_no | week_of | incidents |
|---|---|---|---|
| Lustre mount FAILED | 13 | 2005-08-29 | 1,872 |
| Lustre mount FAILED | 14 | 2005-09-05 | 1,244 |
| Lustre mount FAILED | 15 | 2005-09-12 | 551 |
| ciod socket error | 24 | 2005-11-14 | 213 |
| ciod socket error | 25 | 2005-11-21 | 1,110 |
| ciod socket error | 26 | 2005-11-28 | 789 |
| ciod socket error | 27 | 2005-12-05 | 136 |
| ciod socket error | 28 | 2005-12-12 | 900 |
| ciod socket error | 29 | 2005-12-19 | 186 |
| ciod socket error | 30 | 2005-12-26 | 286 |
| ciod socket error | 31 | 2006-01-02 | 18 |

## The manager: what first, and why believe it

**M1 — lines into incidents, over the whole corpus.** Tool: `episodes(gap_minutes=5)`.

| alert_lines | incidents_5min | lines_per_incident |
|---|---|---|
| 348,460 | 19,250 | 18.1 |

**M2 — ranked by blast radius and persistence.** Tool:
`top_signatures(rank_by="nodes")`; order is `rank_blast_radius + rank_persistence`, dense ranks over
the corpus. A ranking of measured factors, not an impact estimate. The last row is the loudest by
lines, shown for contrast. The manager's view carries no log text and no node IDs — signatures are
identified by a hash (`signature_id`) and category.

| risk_position | lines_position | signature_id | alert_category | component | team | nodes_affected | active_days | episodes_5min | alert_lines | top_node_pct | rank_sum |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 10 | 220716fc4793 | KERNRTSP | KERNEL | compute-platform | 3,394 | 124 | 308 | 3,983 | 0.55 | 4 |
| 2 | 5 | 5a5b95713287 | KERNTERM | KERNEL | compute-platform | 7,650 | 17 | 2,641 | 18,587 | 0.12 | 10 |
| 3 | 3 | e1c84c8186d1 | APPSEV | APP | workload-runtime | 1,024 | 35 | 3,638 | 26,546 | 0.13 | 12 |
| 4 | 6 | 685fb919d4ec | APPSEV | APP | workload-runtime | 1,024 | 27 | 2,282 | 15,273 | 0.17 | 13 |
| 5 | 9 | f2a70c4b0587 | KERNMNTF | KERNEL | compute-platform | 1,024 | 16 | 937 | 5,105 | 0.33 | 16 |
| 12 | 1 | 38a7307dd55b | KERNDTLB | KERNEL | compute-platform | 541 | 11 | 117 | 152,734 | 99.64 | 23 |

**M3 — who owns the alert lines.**

| team | alert_lines | pct_alert_lines |
|---|---|---|
| compute-platform | 284,391 | 81.61 |
| workload-runtime | 63,845 | 18.32 |
| network-fabric | 206 | 0.06 |
| observability | 15 | 0 |
| storage-platform | 3 | 0 |

The demo closes this section with the line the manager's view is required to carry:

> Not established by the logs: cost, downtime, impact on jobs or users, root cause.

## The three answers and the recommended actions

**Engineer.** The loudest signature, `data TLB error interrupt`, is not a fleet problem. 152,734
lines match the phrase; 152,182 of them (99.64%) come from one node, `R30-M0-N9-C:J16-U01`, inside a
single burst from 2005-06-11 17:17:44.898 to 23:39:32.878 — 6 h 21 m 47.98 s. The other two nodes
that ever logged the phrase logged 3 lines each, four days earlier. Counting incidents rather than
lines at a 5-minute gap makes it 117, not 152,734.

*Recommended action:* treat this as one incident on one machine. Pull that node
(`R30-M0-N9-C:J16-U01`, midplane `R30-M0`) for hardware attention, and read the events either side
of the burst's first line before touching anything fleet-wide (see §"Nearby events" — the line
immediately before the storm is a machine check interrupt).

**Team lead.** By incidents the fleet has two leading problems and they are different problems:
`Lustre mount FAILED` (compute-platform) at 3,667 incidents and the `ciod` socket error
(workload-runtime) at 3,638. The line-share and incident-share rankings disagree: compute-platform
holds 81.61% of alert lines but 51.7% of incidents; workload-runtime holds 18.32% of lines but 48% of
incidents. The trend separates them. Lustre is over: 3 active weeks, all of them late August to mid
September 2005 (1,872 / 1,244 / 551), **zero** incidents in the corpus's last 9 weeks, slope −2.501
per week. The ciod socket error is still active: 8 active weeks and all 3,638 of its incidents in
the last 9 weeks, slope +14.806 per week — though its final week holds only 18, so "still active",
not "growing".

*Recommended action:* assign the ciod socket error to workload-runtime now; it is the live one.
Lustre needs no staffing this week.

**Manager.** Ranked by blast radius and persistence rather than by volume, the first priority is
`rts: kernel terminated for reason {n}` (KERNRTSP, KERNEL, compute-platform): 3,394 nodes affected
across 124 active days. The signature with the most lines, `data TLB error interrupt` at 152,734,
is twelfth on this measure — 541 nodes, 11 active days, 99.64% of its lines on one machine. Across
the corpus, 348,460 alert lines are 19,250 incidents, 18.1 lines each. compute-platform owns 81.61%
of the alert lines.

*Recommended action:* prioritise the rts panic, which recurs across thousands of machines over
124 days; schedule the single-node TLB burst as a hardware ticket rather than an operational
emergency; leave the ciod socket error with workload-runtime.

*What this does not establish:* cost, downtime, impact on jobs or users, root cause.

## Observed facts against hypotheses (W1)

| Observed in the data | Hypothesis, not established here |
|---|---|
| 152,183 alert lines on one node, 2005-06-11 17:17:44.606 → 23:39:32.878 | that the node was faulty rather than the workload it ran |
| 1 `machine check interrupt (bit=0x10): L2 DCU read` at 17:17:44.606, then 6,173 DTLB lines in 15 minutes | that the L2 cache error caused the TLB storm — the logs fix the order, not the causation |
| 49,154 alert lines across 22,529 distinct nodes on 2005-06-14 | that this was one event with one cause; we observe the node count, not the reason |
| Lustre incidents stop after week 15 (0 in the last 9 weeks) | that the underlying problem was fixed; the logs show it stopped, not why |
| ciod socket incidents all fall in the last 9 weeks | that its rate is increasing; its final week holds 18 incidents |
| compute-platform owns 81.61% of alert lines | anything about team workload or blame — the map is ours, built from component names |
| 84,253 lines carry the `-` "normal" label while containing `ASSERT` text (see §Limitations) | that the label column is unreliable in general; we measured it on this corpus |

---

# W2 (OpenStack): "Were the instances that were supposed to be slow actually slow?"

## Scope

| dataset | lines | instances | first timestamp | last timestamp |
|---|---|---|---|---|
| OpenStack | 207,812 | 2,069 | 2017-05-14 19:39:01.445 | 2017-05-17 12:02:35.32 |

About 2 days 16 hours, from the Loghub OpenStack log (two files: `openstack_normal.log` and
`openstack_abnormal.log`, plus `anomaly_labels.txt`, which the agent cannot reach — see §Validation).
Time filters: none; the ranking below is over the whole corpus. `spawn_s` is the parsed lifecycle
duration of a server build (`image_s` + `boot_s`), taken from the request lines that carry it.

## The engineer: what is broken, and what the line says

**E1 — latency cannot see the anomaly.** Tool: `durations(metric="api_latency_s", group_by="file")`.

| file_group | api_calls | mean_s | p50_s | p95_s | p99_s |
|---|---|---|---|---|---|
| abnormal | 9,416 | 0.234 | 0.2594 | 0.3771 | 0.5092 |
| normal | 89,317 | 0.2341 | 0.2596 | 0.3826 | 0.5149 |

The two files are the same to three decimal places.

**E2 — the whole error surface.** Tool: `count_events(group_by="level")`.

| level | lines |
|---|---|
| INFO | 204,506 |
| WARNING | 3,118 |
| ERROR | 186 |
| CRITICAL | 2 |

186 ERROR + 2 CRITICAL = 188 lines. Grouped into problems by the lead's view (L3 below), those
188 lines are **not** 188 problems: 184 of them are 8 tracebacks of one bug, and the other 4 are
2 failed token validations.

## The team lead: which work is whose, and what the trend says

**L1 — ranked by spawn time.** Tool: `durations(metric="spawn_s", rank=...)`.

| position | instance_id | spawn_s | image_s | boot_s | source_file |
|---|---|---|---|---|---|
| 1 | a445709b-6ad0-40ec-8860-bec60b6ca0c2 | 50.72 | 44.454 | 6.263 | openstack_abnormal.log |
| 2 | 544fd51c-4edc-4780-baae-ba1d80a0acfc | 41.81 | 34.647 | 7.164 | openstack_abnormal.log |
| 3 | 1643649d-2f42-4303-bfcd-7798baec19f9 | 31.27 | 25.217 | 6.047 | openstack_abnormal.log |
| 4 | ae651dff-c7ad-43d6-ac96-bbcd820ccca8 | 29.46 | 22.444 | 7.014 | openstack_abnormal.log |
| 5 | d7d68893-c44f-4e7c-8d4b-0e7801d62776 | 26.69 | 19.808 | 6.881 | openstack_abnormal.log |

**L2 — the distribution those five sit outside of.** Tool: `durations(metric="phases")`, over every
instance with both ends present.

| spawned | spawn_p50_s | image_p50_s | boot_p50_s |
|---|---|---|---|
| 2,066 | 19.74 | 13.08 | 6.648 |

**L3 — the problems above INFO, with ownership.** Tool: `top_signatures(dataset="openstack")`.

| problem | team | worst_level | incidents_5min | records | tracebacks | lines |
|---|---|---|---|---|---|---|
| token validation failed (identity server 503) | identity | CRITICAL | 2 | 6 | 0 | 6 |
| image cache pass failed (InvalidDiskInfo) | platform-services | ERROR | 8 | 8 | 8 | 184 |
| power-state sync: instance count mismatch | compute-platform | WARNING | 45 | 45 | 0 | 45 |
| vcpu count unavailable (cpu affinity) | compute-platform | WARNING | 10 | 12 | 0 | 12 |
| image cache: unknown base file | image-service | WARNING | 3 | 3,059 | 0 | 3,059 |

Note the fourth row: one root cause, two owners. The `image cache: unknown base file` warnings are
logged by `nova.virt.libvirt.imagecache` (image-service); the `image cache pass failed
(InvalidDiskInfo)` tracebacks are logged by `oslo_service.periodic_task`
(platform-services). Our ownership rule is logger-first, so it splits the same bug across two teams
— a fact worth stating rather than smoothing over.

## The manager: what first, and why believe it

**M1 — problems by severity and incidents.** Tool: `top_signatures(dataset="openstack", persona="manager")`.
The manager's view holds no log text and no instance IDs.

| problem | service | team | worst_level | incidents_5min | records | tracebacks | lines | critical_lines | error_lines | warning_lines |
|---|---|---|---|---|---|---|---|---|---|---|
| token validation failed (identity server 503) | nova-api | identity | CRITICAL | 2 | 6 | 0 | 6 | 2 | 2 | 2 |
| image cache pass failed (InvalidDiskInfo) | nova-compute | platform-services | ERROR | 8 | 8 | 8 | 184 | 0 | 184 | 0 |
| power-state sync: instance count mismatch | nova-compute | compute-platform | WARNING | 45 | 45 | 0 | 45 | 0 | 0 | 45 |
| vcpu count unavailable (cpu affinity) | nova-compute | compute-platform | WARNING | 10 | 12 | 0 | 12 | 0 | 0 | 12 |
| image cache: unknown base file | nova-compute | image-service | WARNING | 3 | 3,059 | 0 | 3,059 | 0 | 0 | 3,059 |

**M2 — the same distribution, split by file**, which is why the file split is not the signal:

| file_group | spawned | spawn_p50_s | spawn_p95_s | spawn_max_s | image_p50_s | image_max_s |
|---|---|---|---|---|---|---|
| abnormal | 197 | 19.79 | 21.1 | 50.72 | 13.08 | 44.454 |
| normal | 1,869 | 19.74 | 20.98 | 22.56 | 13.08 | 15.298 |

The medians differ by 0.05 s while the maxima differ by 28 s. Averages hide all four anomalous
instances; the tail shows them.

The demo closes this section with:

> Not established by the logs: how the anomalies were injected, user impact, cost.

## The three answers and the recommended actions

**Engineer.** Both routes an engineer reaches for first find nothing. Levels: the whole corpus holds
188 lines above INFO out of 207,812. Latency: 0.234 s against 0.2341 s mean between the abnormal and
normal files, p95 0.3771 against 0.3826 — indistinguishable. The error lines are also not 188
problems: 184 are 8 tracebacks of one image-cache bug, and 4 are 2 failed token validations, the
only CRITICAL lines in the corpus.

*Recommended action:* stop filtering on level for this corpus. Rank instances by lifecycle
duration instead (below), and treat the 3,059 `unknown base file` warnings as the same image-cache
root cause as the tracebacks even though a different logger emits them.

**Team lead.** Spawn time separates cleanly: the slowest instances run 50.72 s, 41.81 s, 31.27 s and
29.46 s against a median of 19.74 s over 2,066 instances, and the binding phase is the image phase —
44.454 s on the worst instance against a 13.08 s median — while its boot phase is 6.263 s against a
6.648 s median, i.e. normal. The four slowest instances are exactly the four the corpus's answer key
labelled anomalous; the fifth, `d7d68893`, is not labelled.

*Recommended action:* route the image phase of the build to image-service / platform-services; use
the spawn-time ranking as the triage list. Do not use per-file averages: the abnormal file's median
(19.79 s) is within 0.05 s of the normal file's (19.74 s).

**Manager.** By incidents the leading problem is `power-state sync: instance count mismatch`
(nova-compute, compute-platform) at 45 incidents, followed by `vcpu count unavailable` at 10. The
image-cache failure has fewer incidents (8) but 184 lines and 8 tracebacks, and its sibling warning
adds 3,059 lines under a second team. The 2 CRITICAL lines belong to `token validation failed
(identity server 503)`, owned by identity — the smallest problem by volume and the highest by
severity.

*Recommended action:* fix the image-cache bug once; it is one root cause spanning two owners
(3,059 + 184 lines and 8 tracebacks). Then look at the power-state sync, which is the largest count.
Treat the 2 CRITICAL token failures as a priority despite their 6 lines.

*What this does not establish:* how the anomalies were injected, user impact, cost.

## Observed facts against hypotheses (W2)

| Observed in the data | Hypothesis, not established here |
|---|---|
| 4 instances spawn in 50.72–29.46 s against a 19.74 s median (n = 2,066) | that these four are the *only* slow builds; 26.69 s at position 5 is unlabelled |
| the image phase, not the boot phase, explains the difference (44.454 s against 13.08 s median) | why the image phase is slow — the logs give durations, not causes |
| 184 ERROR lines are 8 identical tracebacks of `InvalidDiskInfo` | that they are 8 separate incidents rather than 8 periodic passes of one ongoing condition |
| 3,059 `unknown base file` warnings share the image-cache root cause | that they are the same defect; they share a module and a file path |
| the 2 CRITICAL lines refuse an API call (token validation) | that the service was down; we observe 2 failed validations, not the outage behind them |
| latency is identical between the normal and abnormal files | that latency is not affected at all — only that this corpus's API latency does not separate them |

---

# The two requirements `make demo` does not cover

`sql/90_queries.sql` runs the two investigations above. The submission also asks the workflow to
demonstrate **full-text search with time filters** and **nearby events**; both are MCP tool calls
rather than demo blocks, so they are recorded here with the SQL that executed, verified on
18 October 2026 against SereneDB 26.09.1.3.

## Full-text search with a time filter

Tool call: `search_logs(dataset="bgl", query="data TLB error interrupt", mode="phrase", since="2005-06-11", until="2005-06-12", persona="engineer")`.

Executed SQL:

```sql
SELECT id AS id, ts AS ts, node AS node, level AS level, team,
       ts_highlight(content, ts_offsets(content)) AS highlight,
       left(content, 300) AS content
FROM bgl_idx
WHERE content @@ ts_phrase('data TLB error interrupt')
  AND ts >= '2005-06-11 00:00:00'::timestamp
  AND ts <  '2005-06-12 00:00:00'::timestamp
ORDER BY ts DESC LIMIT 3;
```

| run | evidence | since → until | total_matches | returned | truncated |
|---|---|---|---|---|---|
| burst evening | E-D69B24 | 2005-06-11 → 2005-06-12 | 152,182 | 3 | true |
| the following day | E-042276 | 2005-06-12 → 2005-06-13 | **0** | 0 | false |

The filter is doing real work: the phrase matches 152,734 lines across the corpus, 152,182 of them
inside the burst's own day and **none at all** the next day. Rows returned carry the node, the level,
the owning team and the highlighted match, and the envelope states the operator (`phrase
(ts_phrase)`) because a count is only meaningful with the operator that produced it.

## Nearby events: what happened either side

Tool call: `nearby_events(dataset="bgl", id=222716, minutes=15, persona="engineer")` — anchored on
the id of the burst's first DTLB line rather than on a timestamp, because an id is exact when
thousands of lines share a millisecond.

Executed SQL:

```sql
SELECT id, ts, alert_category, node, midplane, component, level, team, left(content, 300) AS content
FROM bgl_idx
WHERE ts >= '2005-06-11 17:17:44.898186'::timestamp - INTERVAL '1 minute' * 15
  AND ts <= '2005-06-11 17:17:44.898186'::timestamp + INTERVAL '1 minute' * 15
ORDER BY ts LIMIT 8;
```

Evidence E-D1B193 — 6,174 lines in the ±15-minute window (ids 222715…228888), busiest category
KERNDTLB (6,173) then KERNMC (1). The first rows, verbatim:

| id | ts | category | node | midplane | level |
|---|---|---|---|---|---|
| 222715 | 2005-06-11 17:17:44.605961 | KERNMC | R30-M0-N9-C:J16-U01 | R30-M0 | FATAL |
| 222716 | 2005-06-11 17:17:44.898186 | KERNDTLB | R30-M0-N9-C:J16-U01 | R30-M0 | FATAL |
| 222717 | 2005-06-11 17:17:45.004402 | KERNDTLB | R30-M0-N9-C:J16-U01 | R30-M0 | FATAL |

The line 0.29 seconds before the storm begins is a **machine check interrupt (bit=0x10): L2 DCU
read**, on the same node and midplane. That is the one line that explains why this is a hardware
ticket and not a fleet problem, and it is only visible because the tool reads the neighbourhood
rather than the search results. *Hypothesis, not established:* that the L2 cache error caused the
TLB storm. The logs fix the order of events, not the causation.

---

# Validation (outside the agent)

`make validate` scores the analysis against the answer keys shipped with the corpora, from
`scripts/validate_ground_truth.py`, which no tool and no role view can call
(`docs/validation.md`).

| position | instance_id | spawn_s | is_labelled_anomaly |
|---|---|---|---|
| 1 | a445709b-6ad0-40ec-8860-bec60b6ca0c2 | 50.72 | t |
| 2 | 544fd51c-4edc-4780-baae-ba1d80a0acfc | 41.81 | t |
| 3 | 1643649d-2f42-4303-bfcd-7798baec19f9 | 31.27 | t |
| 4 | ae651dff-c7ad-43d6-ac96-bbcd820ccca8 | 29.46 | t |
| 5 | d7d68893-c44f-4e7c-8d4b-0e7801d62776 | 26.69 | f |

All 4 labelled anomalies land at positions 1–4 of 2,069 by spawn time. `make validate` reports 13/13
expectations holding, including the two negative controls: none of the four labelled instances' 100
lines is above INFO, and API latency is 0.2340 s abnormal against 0.2341 s normal.

**BGL is different and we say so.** Its label column is part of the data the agent can read, so we
do not claim blindness there. Instead we measure agreement: signatures computed from message text
alone agree with the label on 99.9998% of 4,747,963 lines (precision 0.999991, recall 0.999983),
against 0.4065 precision for a FATAL-or-FAILURE filter.

# Limitations

- **The ownership map is ours.** 23 rows, fictional team names, built from logger and component
  names, checked for coverage against the corpus rather than supplied by the organisers. It is a
  demonstration of the ownership dimension, not a claim about a real organisation.
- **BGL's label column is incomplete.** 84,253 lines carry the `-` "normal" label while containing
  `ASSERT` text. We detect alerts from message signatures as well as the label, which is why our
  alert count (348,460) exceeds the labelled count.
- **The incident count is a function of the gap.** 348,460 alert lines are 132 / 117 / 57 incidents
  for one signature at 1 / 5 / 60 minutes; corpus-wide it is 19,250 at 5 minutes. Every answer
  states its gap.
- **A blast radius is a peak, not a sum.** `nodes_affected` counts distinct machines per signature
  or incident; adding those numbers across rows is meaningless and the server refuses to do it.
- **OpenStack problem lines carry no instance id.** Instance ids appear on 51,553 of 207,812 lines
  and on none of the problem lines, so OpenStack blast radius in instances is unmeasurable rather
  than zero; the ranking falls back to lines and incidents and says so.
- **No index-size metric exists** in this SereneDB version (`sdb_indexes()` has no size columns,
  `pg_class` reports `relpages = 0`), so index cost is reported in wall-clock and on-disk bytes.
- **The 30 s and 60 s bench slices crash the engine** — recorded with a reproduction in
  `docs/capabilities.md` §11, together with the workaround for the 1 s and 10 s slices.
- `template_id` is `UNKNOWN` throughout: the corpus ships no template IDs, so signatures are
  computed from message text (`{n}` masks digits, `{uuid}` masks identifiers).
