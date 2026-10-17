# PROGRESS — Adnan's lane

Deadline: Sun 18 Oct, 23:59 · Current team stage: 0–1 (re-checked on a second machine) · Status: two-hour list in progress

## Stage log (team plan §11)

| Team stage | Window | Adnan's part | Result |
| --- | --- | --- | --- |
| 0–1 Probe, data layer | Done by Sat 12:00 | Re-probe, verify headline numbers, port `sql/50_roles.sql`, extend `os_sig` | Done Sat 13:30 on a second machine: gate met (4,747,963 / 207,812; 348,460 → 19,250); burst corrected to 152,183; partial-index row corrected; roles and W2 views in |
| 2 MCP skeleton | Sat 12:00–14:00 | Golden SQL for the first three tools | |
| 3 W1/W2 tools | Sat 14:00–17:00 | Views for `top_signatures`, `trend`, `episodes`, `durations`, `ownership` | |
| Q&A | Sat 17:00–20:00 | Questions from team plan §13; answers into `PLAN.md` | |
| 4 Roles, contract, lints | Sat 20:00–24:00 | Role views and grants | |
| Sleep | Sun 00:00–08:00 | OTel bench in the background | |
| 5 Validation, eval | Sun 08:00–12:00 | Ground-truth validation script | |
| 6 README, clean-check, slides | Sun 12:00–15:00 | Data, loader, ownership, limitations sections | |
| 7 Video | Sun 15:00–19:00 | Real numbers on screen | |
| 8 Submission | Sun 19:00–22:00 | Team plan §15 checklist | |

## Requirements tracker (brief + team plan §15)

| Requirement | Status | Proof (file, command or evidence ID) |
| --- | --- | --- |
| An answer for each role with relevant evidence, fitting detail and a role-suited next step | ☐ | |
| Retrieval and aggregation used on BGL and on OpenStack | ☐ | |
| At least one answer uses full-text search | ☐ | |
| At least one whole-corpus aggregation (per dataset or team), with scope and filters stated | ☐ | |
| Practical recommendations: what to check or fix first, and why | ☐ | |
| Tools with clear descriptions of purpose, inputs and outputs | ☐ | |
| Executed queries and results shown; hypotheses and limitations labelled; numeric lint passes | ☐ | |
| Clean checkout: start SereneDB, load BGL and OpenStack, start the agent (`make clean-check`) | ☐ | |
| Schema, loading scripts and ownership table in the repo (organizers' Q&A) | ☐ | |
| Public repo, MIT licence, README covering workflow, setup, running and limitations | ☐ | |
| Disclosure section: models, tools, what was built in the window | ☐ | |
| Worked investigations W1 and W2 with search and aggregation, and what the data does and does not establish | ☐ | |
| Video of at most 5 minutes plus a 3-minute cut, and slides | ☐ | |
| SereneDB starred on GitHub; docs MCP connected | ☐ | |
| Optional: workspace index (re-probed; result reported either way) | ☐ | |
| Optional: huge data (OTel Parquet) with data volume, times and machine | ☐ | |
| Bonus: role scope enforced by the database | ☐ | |
| Bonus: logs correlated with traces or metrics | ☐ | |

## Done

- **Step 0, local load (Sat 17 Oct, 11:40–11:50).** Zenodo 8196385 `BGL.zip` (57,489,019 B) and `OpenStack.tar.gz` (5,394,691 B), MD5s match the record, unpacked into `data/loghub/`; `make parse`; bootstrap SQL through the container's `psql`. Gate met: 4,747,963 / 207,812 rows, 348,460 alert lines → 19,250 episodes (1,377 global). `8aff69d fix(data): …` — `parse.py` ignored the `--in/--out` the Makefile passed; `fetch` now unpacks into `data/loghub`, which is what derive reads.
- **Item 1, probe (Sat 17 Oct, 11:50–12:04).** `6eb8b07 fix(probe): …`. `scripts/probe_capabilities.sh` rewritten against `bgl_ev`/`bgl_idx`/`os_ev`/`os_idx` (it queried the old `bgl`/`openstack` tables), 90 rows each with the outcome `docs/capabilities.md` claims, DRIFT on any difference, its own `exhibit_probe` database (recreated, dropped), idempotent (two runs identical). `make probe` pointed at it (it named a non-existent `sql/00_probe.sql`). **Broke one row**: the partial inverted index restricts on pattern B; the old "no effect" measurement was on a search table. Dictionary row holds. `docs/capabilities.md` §1, §2, §3, §7, §8 updated with the statements and results.

  | Acceptance (item 1) | Result |
  | --- | --- |
  | `make probe` runs on the current schema | 90 rows (91 after item 2), 0 drift, exit 0, ~85 s |
  | Partial-index row re-measured, statements recorded | **Corrected**: `p_part` named → 34,056 = full index + window; 0 rows outside; holds when built before the load, after an UPDATE (34,057), and for an empty predicate (0). Ignored only on a `storage = 'search'` table (121,498) |
  | Dictionary row re-measured | **Holds**: `AS split_text(…)` → `syntax error at or near "AS"`; parenthesised `template = 'text'` form PASS; all five §5 lexize outputs identical |
  | Idempotent | two consecutive runs identical apart from timings; no `probe_*` role or database left behind |

- **Item 2, independent verification (Sat 17 Oct, 12:05–12:25).** `sql-verifier` recomputed the headline numbers with fresh SQL, twice each (raw Parquet and `bgl_ev`), without the views or the smoke file; its SQL is `tests/golden/headline_numbers.sql`. I re-ran the mismatch myself before accepting it. **One headline number was wrong**: the one-node burst is 152,183 lines, not 136,209. `sql/99_smoke.sql` §4 now takes the whole day per node and §4b computes both rows instead of printing literals.

  | Acceptance (item 2) | Stated | Independent | Verdict |
  | --- | --- | --- | --- |
  | Alert lines, `label <> '-'` (raw and `bgl_ev`) | 348,460 | 348,460 | MATCH |
  | Episodes, 5 min, signature × midplane (LAG start rows; groups + gaps > 300 s) | 19,250 | 19,250 | MATCH |
  | Episodes, 5 min, signature only | 1,377 | 1,377 | MATCH |
  | Tie / boundary sensitivity | — | none: no shared `ts`, no gap within 1 ms of 300 s | — |
  | One-node burst 2005-06-11 | 136,209 lines, 1 node, 5h43m, 39% | **152,183** lines, 1 node (`R30-M0-N9-C:J16-U01`), 17:17:44 → 23:39:32 = 6h21m48s, 43.67% | **MISMATCH**: 136,209 is the burst cut at `ts < 23:00` (15,974 lines after 23:00 dropped) |
  | Fleet day 2005-06-14 / 2005-06-13 | 49,154 on 22,529 / 17,409 on 16,644 | same | MATCH |
  | `make smoke` §4b computes, not literals | literals | 152,183 / 1 vs 49,154 / 22,529 | fixed |

- **Item 3, roles (Sat 17 Oct, 12:25–12:55).** `sql/50_roles.sql` ported from the OTel corpus to `bgl_ev`/`os_ev`. Three LOGIN roles (no password: trust auth on loopback), created once with psql `\if` (no `CREATE ROLE IF NOT EXISTS` or `DROP OWNED BY` here) and never dropped; views dropped and recreated each run; one GRANT per table (no lists). `sql/30_views.sql` gains `signature_id` (12 hex of `md5(signature)`) on `bgl_sig`, `os_sig`, `bgl_incident` and `bgl_signature_incidents`, so the manager can name a problem without its text. `make bootstrap` now ends with `roles`.

  | Acceptance (item 3) | Result |
  | --- | --- |
  | Engineer: raw lines and search on `bgl_idx` by name | `bgl_idx @@ 'ciod'` → 350,567 as `exhibit_engineer`; SELECT on every table and view |
  | Lead: signatures by team, trend, incidents; no raw lines | `lead_bgl_daily` (68,952 rows, sums to 4,747,963), `lead_os_hourly` (2,046 rows, 207,812), `bgl_incident`, `bgl_signature_incidents`, `os_instance_durations`, `owner_map`, `mgr_*`; `bgl_ev` and `bgl_idx` refused |
  | Manager: no log text, keeps component and team | `mgr_bgl_risk` (100 signatures, 348,460 alert lines, 19,250 episodes), `mgr_os_risk` (29 rows, 3,306 lines above INFO), `mgr_rollup_daily` (4,955,775 lines); columns hold no `content`, `signature`, `node` or `logger`; `bgl_ev`, `lead_bgl_daily` and `bgl_incident` refused |
  | Access matrix (16 relations × 3 roles) | engineer 16 · lead 10 · manager 3, exactly as designed |
  | Idempotent | two full rebuilds (derive → index → views → roles, 26 s together) and a roles-only re-run print identical output |
  | Headline numbers after the view change | 348,460 → 19,250 → 1,377 unchanged; 152,183 / 1 vs 49,154 / 22,529 |
  | Speed | every role view answers in under 300 ms (`lead_bgl_daily` 290 ms, `mgr_bgl_risk` 256 ms) |

- **Item 4, W2 views (Sat 17 Oct, 12:55–13:30).** `os_sig` gains `level_rank`, `record_key` (lines of one log record: a traceback's 23 lines share file, pid, ts, logger, level), `problem` (our label from logger + level, `'NONE'` for INFO), `event` (lifecycle step on the exact masked message) and `took_s`. New views: `os_episode` / `os_incident` / `os_problem_incidents` (problem incidents at a 5-minute gap, with records and tracebacks), `os_latency_by_file`; `os_instance_durations` gains the lifecycle phases (claim, image, boot, run, teardown, destroy, dealloc, `lifetime_s`) and its `team` is now the owning team instead of `'NONE'`. Roles: engineer and lead get the new views; manager's `mgr_os_risk` is now one row per problem and `mgr_os_lifecycle` gives the duration distribution without instance IDs. `make smoke` §6b, §7, §7a print the W2 numbers.

  | Acceptance (item 4) | Result |
  | --- | --- |
  | Imagecache traceback grouping | 184 ERROR lines → **8 incidents = 8 records = 8 tracebacks** (23 lines each, ≥ 58 min apart), all `InvalidDiskInfo` |
  | CRITICAL auth lines | 6 lines (2 CRITICAL, 2 ERROR, 2 WARNING) → **2 incidents**, 1 request each, 06:25 on 05-16 and 05-17; the only CRITICAL lines |
  | "Unknown base file" warnings | 3,059 lines → **3 incidents** at 5 min = exactly the 3 log files (270 / 838 / 1,951): never quiet for 5 minutes inside a file, a persistent condition |
  | Lifecycle durations | the 4 labelled instances rank 1–4 by spawn (50.72 / 41.81 / 31.27 / 29.46 s) **and** by image phase (44.454 / 34.647 / 25.217 / 22.444 s vs median 13.08); boot 6.0–7.2 s vs median 6.65: the time is in image creation |
  | Latency, normal vs abnormal file | mean 0.2340 vs 0.2341 s, p95 0.3771 vs 0.3826 s (`quantile_cont`) |
  | Lifecycle events matched | claim_start 2,065 · image_create 2,066 · vm_started 2,066 · spawned 2,066 · terminate 2,064 · vm_stopped 2,067 — equal to the per-signature counts |
  | Manager scope | `mgr_os_risk` (5 problems, 68 incidents) and `mgr_os_lifecycle` carry no text, no logger, no instance ID |
  | Independent check | `sql-verifier`, fresh SQL on the raw Parquet and `os_ev`: all six W2 claims MATCH (`tests/golden/w2_numbers.sql`, 46 rows `t`); shortest gap between tracebacks 58m44.9s; image median over 2,065 instances |

## Decisions

- The team plan governs schedule, split and stage numbers; `docs/build-plan.md` is the design reference.
- To settle with Arnie: manager answers name affected components and owning teams (the brief asks for them), never raw log text. PLAN.md §7 already reads this way ("affected component family and owning team", never node IDs or logger names); the role views follow it.
- The probe creates objects only in `exhibit_probe`, never in `postgres` or `exhibit_scratch` (left for hand tests and `serenedb-expert`).

## Measured numbers

| What | Value | Command or evidence | When |
| --- | --- | --- | --- |
| Machine | Windows 11, Docker Desktop 29.7.2, image amd64 `sha256:018a3187c193…`, 16 vCPU, 7.6 GB Docker VM | `docker info` | Sat 11:40 |
| Parse parity | BGL 4,747,963 of 4,747,963, 0 unusable; OpenStack 207,812, 8 unusable | `logs/parse.log` (`make parse`) | Sat 11:45 |
| Derive / index / views | 10.0 s / 2.4 s / 0.4 s wall clock (8.7 s for `bgl_ev`) | bootstrap SQL with `\timing` | Sat 11:48 |
| Headline numbers | 348,460 → 19,250 (5 min, signature × midplane) → 1,377 (signature); **152,183** alert lines on 1 node 2005-06-11 17:17:44 → 23:39:32 (6h22m, 43.67%) | `sql/99_smoke.sql` §2, §4; `tests/golden/headline_numbers.sql` | Sat 12:25 |
| `statement_timeout` | accepted, **not enforced** (warning; `SET … '1ms'` then a 200 ms query completes) | `make probe` §8 | Sat 12:20 |
| Partial index build | 239–315 ms (424,614 rows) vs 1,163–1,248 ms full (4,747,963), three runs | `make probe` §5 | Sat 12:30 |
| Partial index query | 1.60–1.84 ms named vs 1.96–2.29 ms full + window, median of 21, three runs | `make probe` §5 | Sat 12:30 |
| BGL clock | `ts` = US Pacific wall clock (epoch − 7 h to 2005-10-30 01:18, − 8 h after); 49 rows in the repeated hour, 0 alerts | `docs/data-notes.md` | Sat 12:35 |

## Background jobs

| Job | PID | Log | Started | Status |
| --- | --- | --- | --- | --- |
| | | | | |

## Handoffs to Arnie

- **Workspace indexes are back on the table (your optional `create_index` / `drop_index`).** On pattern B a partial inverted index restricts when named: `CREATE INDEX <name> ON bgl_ev USING inverted (id, content log_text, ts, …) WHERE <predicate>`, then `VACUUM (REFRESH_TABLE) bgl_ev`, then `FROM <name> WHERE content @@ …` returns only rows matching the predicate. The win is build time (about a fifth for a 9% window), not query time (about 0.4 ms). `sdb_indexes()` does not show the predicate, so the tool must record it. PLAN.md §14 item 4 and §16 still say "no effect"; yours to update. Details: `docs/capabilities.md` §3.
- `make probe` works again (`PSQL=… DATA=…` pass through); no change to your code.
- **The one-node burst number in PLAN.md is wrong: 152,183, not 136,209** (verified twice, `tests/golden/headline_numbers.sql`). PLAN.md is yours, so I have not touched it. Lines to change: 124 (table row: "2005-06-11 17:17 → 23:39 | 152,183 | 1"), 127 ("39%" → "44% of all alert lines … in under six and a half hours"), 308 (W1 engineer: "one node emitting 152,183 lines in 6h22m"), 497 (appendix). The comparison is stronger, not weaker: 152,183 lines on 1 node against 49,154 on 22,529. Fixed in my files: `CLAUDE.md`, README (also 18,770 → 19,250 episodes), `docs/build-plan.md` §0, `docs/data-notes.md`, `sql/99_smoke.sql`. Any slide or video script that has 136,209 or "5h43m" needs the same change.
- **Roles are in the database now (`sql/50_roles.sql`); `datasets.py` needs the per-role relations.** Logins `exhibit_engineer`, `exhibit_lead`, `exhibit_manager` (the names in `.env.example`), no password. Connect as the role, or as `postgres` and `SET ROLE`.
  - engineer: unchanged, everything you query today, including `bgl_idx` / `os_idx` by name.
  - lead: no per-line relation and **no full-text search** (the database refuses `bgl_idx`, because a search on an index is checked against `bgl_ev`). Use `lead_bgl_daily` (day, team, component, level, alert_category, is_alert, signature_id, signature, lines, nodes, midplanes), `lead_os_hourly` (hour, team, service, logger, level, signature_id, signature, lines, instances, requests, http_errors), `bgl_incident`, `bgl_signature_incidents`, `os_instance_durations`, `owner_map`. `search_logs` for the lead should return "not permitted for this role". `nodes` / `instances` / `requests` are distinct per bucket: never sum them.
  - manager: `mgr_bgl_risk` (signature_id, alert_category, component, team, worst_level, alert_lines, episodes_5min, nodes_affected, midplanes_affected, peak_nodes_per_episode, active_days, longest_episode, first/last_seen), `mgr_os_risk` (signature_id, service, team, worst_level, lines, instances_affected, requests_affected, active_hours, first/last_seen; above INFO only), `mgr_rollup_daily` (dataset, day, team, component, category, level, lines). A problem is named by `signature_id` + `alert_category` + component + team, never by text. The views carry factors only; the ranking by blast radius and persistence is your `top_signatures` `rank_by`.
  - New column `signature_id` on `bgl_sig`, `os_sig`, `bgl_incident`, `bgl_signature_incidents`: the join key between the lead's and the manager's views.
  - **Changed in item 4:** `mgr_os_risk` is now one row per *problem* (dataset, problem, service, team, worst_level, incidents_5min, records, tracebacks, lines, critical_lines, error_lines, warning_lines, requests_affected, first/last_seen), no longer per signature_id. New `mgr_os_lifecycle` (file_group, instances, spawned, spawn p50/p95/max, image p50/max, boot p50/max).
- **W2 views for your `episodes`, `durations` and `top_signatures` on OpenStack** (`sql/30_views.sql`): `os_problem_incidents` (one row per problem: episodes, records, tracebacks, lines by level, team), `os_incident` (one row per incident), `os_episode` (per line, engineer only), `os_instance_durations` (now with claim_s, image_s, boot_s, run_s, teardown_s, destroy_s, dealloc_s, lifetime_s, source_file, and the real owning team), `os_latency_by_file` (mean, p50, p95, p99 per file and per normal/abnormal group). `os_sig` adds `level_rank`, `record_key`, `problem`, `event`, `took_s`. The OpenStack episodes gap is fixed at 5 minutes in the view, as for BGL; if `episodes` must take 1/5/60 on OpenStack too, the tool needs the parameterised SQL pattern rather than the view.
- **PLAN.md OpenStack wording (yours to change; numbers verified, `tests/golden/w2_numbers.sql`):** §17 "188 error lines = 8 tracebacks of one bug + 6 CRITICAL auth lines" is wrong (184 + 6 = 190, and only 2 lines are CRITICAL). Suggested: "188 ERROR + CRITICAL lines = 184 lines in 8 tracebacks of one imagecache bug + 4 token-validation lines (2 failed validations, 6 lines with their 2 WARNINGs)". §4 "188 error lines ≈ 8 incidents of 1 bug" has the same problem, and "184 ERROR lines, all from `nova.virt.libvirt.imagecache`" should say *logged by `oslo_service.periodic_task`*, with imagecache in the stack frames. §9 W2 manager "six lines of CRITICAL auth failures" → "2 CRITICAL token-validation failures (6 lines)". `docs/build-plan.md` §0 says "6 CRITICAL auth lines" too; I fix that one.
- **Ownership trap worth a demo line:** the imagecache traceback is logged by `oslo_service.periodic_task`, so logger-first precedence gives it to `platform-services`, while the imagecache warnings go to `image-service`. One bug, two teams. Your lead answer should say so; changing `data/ownership.csv` is our call together.
  - Your evidence ledger: every role needs `SELECT` / `INSERT` on `exhibit_evidence` once it exists. Add the grants to `sql/50_roles.sql` (one table per GRANT statement) or tell me the table name and I will.
  - `make bootstrap` now runs `roles` last; `sql/30_views.sql`'s `DROP … CASCADE` removes the role views, so never run views without roles after it.
- **`statement_timeout` is not enforced by the server** (it warns and runs on). Rule 9's 30 s limit on tool paths has to be enforced in your code: e.g. a timer that calls `conn.cancel()`, or run the query in a thread and cancel on timeout. Do not rely on `SET statement_timeout`.

## Open issues

- README's `APPSEV` "7,036 episodes" is per **alert category** × midplane, not per signature like the rest of that paragraph (now labelled; checked: 7,036 by category × midplane, 7,165 summed over its 5 signatures).
- On a search table the partial-index "rows outside" count came out 87,443 in the probe and 87,442 by hand (the complement is 87,442). Pattern A only, not used; recorded, not chased.

## Next

- Team stage 3 (Sat 14:00–17:00): views and golden SQL behind `top_signatures`, `trend`, `episodes`, `durations`, `ownership`; write `sql/90_queries.sql` so `make demo` prints W1 and W2 (the Makefile names it; it does not exist yet). W2's numbers are already in `make smoke` §6b–§7a.
- Before the Q&A: agree with Arnie on the PLAN.md burst correction and on the imagecache ownership split.
