# PROGRESS — Adnan's lane

Deadline: Sun 18 Oct, 23:59 · Current team stage: 7 (video) · Status: stages 0–6 merged to `main`; the MCP server also runs as a live HTTP demo endpoint (round 6 below). Left: deck export, video, submission §15

## Stage log (team plan §11)

| Team stage | Window | Adnan's part | Result |
| --- | --- | --- | --- |
| 0–1 Probe, data layer | Done by Sat 12:00 | Re-probe, verify headline numbers, port `sql/50_roles.sql`, extend `os_sig` | Done Sat 13:30 on a second machine: gate met (4,747,963 / 207,812; 348,460 → 19,250); burst corrected to 152,183; partial-index row corrected; roles and W2 views in |
| 2 MCP skeleton | Sat 12:00–14:00 | Golden SQL for the first three tools | |
| 3 W1/W2 tools | Sat 14:00–17:00 | Views for `top_signatures`, `trend`, `episodes`, `durations`, `ownership` | SQL side done Sat 13:05: 3 views, `sql/90_queries.sql` (`make demo`) prints W1 and W2 per role under `SET ROLE`, every number computed and independently verified; 3 §9 statements wrong, corrections handed to Arnie. Tool side (Arnie) pending |
| Q&A | Sat 17:00–20:00 | Questions from team plan §13; answers into `PLAN.md` | |
| 4 Roles, contract, lints | Sat 20:00–24:00 | Role views and grants | Done early (Arnie's lints, `0c1d9df`); roles were in since item 3 |
| Sleep | Sun 00:00–08:00 | OTel bench in the background | Bench done Sat evening instead (item 7) |
| 5 Validation, eval | Sun 08:00–12:00 | Ground-truth validation script | Done Sat 16:25: `scripts/validate_ground_truth.py` (item 6). PLAN §11 called it done earlier, but the script had never been committed |
| 6 README, clean-check, slides | Sun 12:00–15:00 | Data, loader, ownership, limitations sections | Done Sat evening (item 8): LICENSE, README fixes, the slide deck, fresh clone on Windows |
| 7 Video | Sun 15:00–19:00 | Real numbers on screen | |
| 8 Submission | Sun 19:00–22:00 | Team plan §15 checklist | |

## Requirements tracker (brief + team plan §15)

| Requirement | Status | Proof (file, command or evidence ID) |
| --- | --- | --- |
| An answer for each role with relevant evidence, fitting detail and a role-suited next step | ◐ tools and lints done; the answers themselves are the video's | `make demo` per role; `make eval` 15/15 across the three roles (answers pass `lint_answer`) |
| Retrieval and aggregation used on BGL and on OpenStack | ☑ | `search_logs` / `count_events` / `episodes` / `durations` on both; `make demo` W1 (BGL) and W2 (OpenStack) |
| At least one answer uses full-text search | ☑ | `search_logs` (`@@ ts_phrase` on `bgl_idx`), eval Q03; demo W1 E2 |
| At least one whole-corpus aggregation (per dataset or team), with scope and filters stated | ☑ | `count_events(bgl, group_by=team)` envelope (`scope`, `measure`); demo W1 L1, L3 |
| Practical recommendations: what to check or fix first, and why | ◐ the ranked evidence exists; the wording is the client's | demo W1 M2 (risk order with reasons), W1 L4 (ciod still growing, Lustre healed) |
| Tools with clear descriptions of purpose, inputs and outputs | ☑ | `src/exhibit/server.py` (12 tools, descriptions), README tool table |
| Executed queries and results shown; hypotheses and limitations labelled; numeric lint passes | ☑ | every envelope carries `query`; `lint_answer`; `make eval` lints each answer |
| Clean checkout: start SereneDB, load BGL and OpenStack, start the agent (`make clean-check`) | ☑ | Arnie: Linux clean clone; Adnan: Windows fresh clone (item 8) |
| Schema, loading scripts and ownership table in the repo (organizers' Q&A) | ☑ | `sql/10_derive.sql` … `sql/55_evidence.sql`, `scripts/parse.py`, `data/ownership.csv` |
| Public repo, MIT licence, README covering workflow, setup, running and limitations | ◐ public at submission | `LICENSE` (item 8), README quickstart, Windows note, limitations |
| Disclosure section: models, tools, what was built in the window | ☑ | `docs/disclosure.md` (Arnie) |
| Worked investigations W1 and W2 with search and aggregation, and what the data does and does not establish | ☑ | `make demo`; `docs/validation.md`; "Not established" per manager step |
| Video of at most 5 minutes plus a 3-minute cut, and slides | ◐ slides done, video is stage 7 | slide deck (item 8), every number with its source command |
| SereneDB starred on GitHub; docs MCP connected | ◐ docs MCP connected (`.mcp.json`, used for the bench) | starring is a click each of us makes |
| Optional: workspace index (re-probed; result reported either way) | ◐ re-probed, not a tool | `docs/capabilities.md` §3 (partial index restricts on pattern B) |
| Optional: huge data (OTel Parquet) with data volume, times and machine | ☑ | `make bench`, `make bench-ladder`, `bench/README.md`, `docs/capabilities.md` §11 (item 7) |
| Bonus: role scope enforced by the database | ☑ | `sql/50_roles.sql` scope proof (`logs/roles-s3.log`: 3 roles read their views, 6 statements refused); `make demo` runs every step under its role with `SET ROLE` |
| Bonus: logs correlated with traces or metrics | ◐ log-side only | bench B5: one OTel trace id → its log lines across 5 services (no span data, so no real trace join) |

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

- **Stage 3, SQL behind the W1/W2 tools (Sat 17 Oct, 12:40–13:05).** `sql/30_views.sql` gains `bgl_signature_stats` (every ranking factor per alert signature: lines, 5-min incidents, nodes, midplanes, peak nodes per incident, active days, longest incident, loudest node and its share, blast-radius and persistence ranks), `bgl_episode_sensitivity` (incidents at 1 / 5 / 60 min, per midplane and global) and `ownership_coverage` (lines and problem lines per team and matching key, both datasets). `mgr_bgl_risk` is now `bgl_signature_stats` without text or node ID, plus `top_node_pct` and the two ranks. New `sql/90_queries.sql` (`make demo`): W1 and W2, engineer → lead → manager, each step named after its tool and run under its role with `SET ROLE`, every number computed; the label check is a separate validation block. `sql-verifier` recomputed all 15 claim groups on the raw Parquet without the views: `tests/golden/stage3_numbers.sql`, 76 rows `t`, 0 `f`, twice (`logs/golden-stage3.log`). Found on the way: password-less roles cannot log in, and the Windows host needs a password for `postgres` (`docs/capabilities.md` §6).

  | Gate (team plan §11 Stage 3, Adnan's part) | Command or proof | Result | Verdict |
  | --- | --- | --- | --- |
  | `make demo` prints both investigations | `sql/90_queries.sql` through the container's psql (no `make` here), `logs/s3-demo-1.log` | W1 and W2, 3 roles each, exit 0, 2.4 s | PASS |
  | W1 engineer: DTLB 152,734 lines; one node | demo E1–E3 | 152,734 by signature and by `@@ ts_phrase`; 99.64% from one node; 152,183 alert lines on 1 node in 6h22m (§9 still says 136,209 / 5h43m: handoff) | PASS, §9 text wrong |
  | W1 lead: 91% compute-platform; ciod and Lustre lead by episodes | demo L1–L4 | 91.09% of lines but **81.61% of alert lines**; Lustre 3,667 and ciod 3,638 incidents, at most 8 nodes per incident (1,024 overall) | PASS, §9 text wrong (handoff) |
  | W1 manager: 348,460 → 19,250, ranked by blast radius and persistence, cost not established | demo M1–M3 | 348,460 → 19,250 (18.1 lines per incident); `rts panic` first, DTLB 12th; "Not established" printed | PASS |
  | §8: 132 / 117 / 57 for one signature | demo E4 | DTLB 132 / 117 / 57 (midplane), 37 / 37 / 16 (global) | PASS |
  | W2 engineer: latency identical | demo E1 | mean 0.2340 vs 0.2341 s, p95 0.3771 vs 0.3826 | PASS |
  | W2 lead: 4 labelled at positions 1–4 | demo L1 + validation block | 50.72 / 41.81 / 31.27 / 29.46 s, all labelled; position 5 (26.69 s) unlabelled | PASS |
  | W2 manager: 8 imagecache incidents; CRITICAL auth | demo M1 | 8 incidents = 8 tracebacks (184 lines); 2 CRITICAL token-validation incidents, 6 lines (§9 "six lines of CRITICAL" wrong: handoff) | PASS, §9 text wrong |
  | Every demo number independently verified | `tests/golden/stage3_numbers.sql` + `tests/golden/w2_numbers.sql` | 76 / 76 and 46 / 46 `t` | PASS |
  | `make bootstrap smoke` green, idempotent | full rebuild ×3 (`logs/s3-*-{1,2,3}.log`) | 14.4 s; smoke, roles and demo output identical across rebuilds; 4,747,963 / 207,812; 348,460 → 19,250 → 1,377 | PASS |
  | Role scope holds | `sql/50_roles.sql` scope proof | lead reads 19,250 / 1,377 from `bgl_episode_sensitivity`; manager refused `bgl_signature_stats` (and 3 others), lead refused 2 | PASS |

- **Item 5, audit of merged `main` (Sat 17 Oct, 16:05–16:15).** Pulled `dbddf95`, read PLAN / PROGRESS / Makefile / README / disclosure / the code paths, and ran everything from this Windows box. The container had been started without `SERENEDB_HOST_AUTH_METHOD=trust`, so the Python side could not log in from the host; recreated it with the flag (volume kept), and my database predated `sql/55_evidence.sql`, so a full bootstrap first.

  | Check | Result |
  | --- | --- |
  | `make bootstrap` (derive → index → views → roles → evidence) | 17.8 s; the only errors are the scope proof's 6 intended denials, identical to `logs/roles-s3.log` |
  | `make smoke`, `make demo` | exit 0; demo identical to `logs/demo-pass3.log` apart from timings |
  | `make check` (Arnie) | **101/101**, stock MCP client PASS, once `PYTHONUTF8=1` (cp1252 console cannot print `✓`; now exported by the Makefile) |
  | `make eval` (Arnie) | **15/15**, 19/19 figures, 6 refusals |
  | W2 ownership split (Arnie's item 4) | holds: `oslo_service.periodic_task` ERROR 184 → platform-services; `nova.virt.libvirt.imagecache` WARNING 3,059 → image-service; auth_token 4 → identity |
  | Gaps found | `scripts/validate_ground_truth.py` cited by PLAN §7/§11, `docs/disclosure.md` and `evals/golden.sql` but never committed (item 6); `sql/70_bench.sql` missing so `make bench` failed (item 7); no `LICENSE`; Makefile `up` without the auth flag; README stale (94 checks, 11 tools, `sql/90` "Stage 3"); a stray empty `-Force/` directory |
  | Defects in Arnie's files (not edited; handoff round 4) | `durations` orders without a tie-breaker; the stock client asserts 11 of 12 tools; `.mcp.json` registers only the docs server; PLAN §9 reads the M2 rank sum (23) as a position; `evals/golden.sql` and `docs/disclosure.md` wording |

- **Item 6, ground-truth validation (Sat 17 Oct, 16:15–16:25).** `65ed218 feat(validate): …`. `scripts/validate_ground_truth.py` (`make validate`) runs outside the agent: it reads `anomaly_labels.txt` from disk, asserts that no MCP tool and no relation or column carries the key, scores the lead's own `durations` ranking (evidence id printed, so `verify_evidence` re-runs it), and for BGL measures whether text-only signatures reproduce the label (the label is visible to the agent, so the script says so instead of claiming blindness). `docs/validation.md` writes it up.

  | Expectation (13/13, identical over three runs) | Result |
  | --- | --- |
  | Out of reach | none of the 12 tools reads labels; 0 relations, 0 columns named after the key |
  | OpenStack: labelled instances by spawn, of 2,069 | positions 1, 2, 3, 4 (50.72 / 41.81 / 31.27 / 29.46 s); agent's top 10 = scored top 10; position 5 unlabelled (`d7d68893`, 26.69 s, abnormal file); image phase alone also 1–4; chance 1 in 761,325,852,001 |
  | Negative controls | 0 of their 100 lines above INFO; API latency mean 0.2340 vs 0.2341 s, p95 0.3771 vs 0.3826 s |
  | BGL: signature vs label | 99.9998% line agreement (9 lines differ), 4 of 29,670 signatures mixed; detector TP 348,454 / FP 3 / FN 6 (precision 0.999991, recall 0.999983) vs FATAL/FAILURE filter precision 0.406502, recall 1 |
  | Found on the way | `arg_max` broke a 1–1 tie differently between runs (TP 348,455 then 348,454): ties now go to `-` via `row_number()`; `= ANY(%s)` needs `::VARCHAR[]`; `NULL`s sort last under `DESC` (`docs/capabilities.md` §4) |

- **Item 7, huge-datasets bench (Sat 17 Oct, 16:25–18:05).** `sql/70_bench.sql` (`make bench`, `BENCH_SECONDS`), `bench/run_ladder.sh` (`make bench-ladder`, sizes each index from its directory under `engine_search/`), `bench/README.md`, `docs/capabilities.md` §11. Over an hour went into nine server crashes before the cause showed: **`enable_external_file_cache` (on by default) defeats row-group pruning**, and big unpruned remote reads end in SIGSEGV (same PC every time). With it off, a time slice of the 1B-row file prunes to its row groups and an inverted index on a view over it builds. Filtering on `"Timestamp"` (ns) instead of `"TimestampTime"` read the whole 1.95 GB column (7 min 57 s for one second of data).

  | Measured (16 vCPU, ~6 MiB/s to S3) | 1 s slice | 10 s slice | 30 s / 60 s |
  | --- | --- | --- | --- |
  | Row groups touched (of 1,624) | 2 | 10 | 27 / 52 |
  | `Body` read cold, bytes in | 99.8 MiB (of 9.07 GB) | 142.7 MiB | 233.8 / 367.3 MiB |
  | Index build on the remote view | 536,041 rows, 24.8–32.2 s | 5,275,597 rows, 60.0 s | **SIGSEGV** both |
  | Index on disk | 14,676 KB | 136,472 KB | — |
  | Phrase + facet on the slice index | 28,520 hits, 8–18 ms | 290,473 hits, 13 ms | — |
  | Footer metadata / `count(*)` of 1B rows | 1.4–3.3 s / 0.1–0.8 s | | |
  | Local: index on a view over `bgl.parquet` vs same columns on `bgl_ev` | 0.69–1.25 s vs 1.07–1.99 s; both 152,734 (phrase) and 350,567 (`ciod`), = `bgl_idx` | | |

- **Item 8, Stage 6 (Sat 17 Oct, 17:30–18:30).** `LICENSE` (MIT); `.gitattributes` (scripts, Makefile and SQL stay LF on a Windows checkout, where `core.autocrlf` would otherwise give bash `set -euo pipefail\r`); README (validation and huge-data sections, 101 checks, 12 tools, repo map, Windows note, limitations); `docs/slides.md` (every slide figure → its command); the slide deck (13 slides, Claude artifact, private until shared). The team plan §11 Stage 6 gate on a machine other than Arnie's:

  | Gate | Command or proof | Result | Verdict |
  | --- | --- | --- | --- |
  | Fresh clone runs the whole sequence | `git clone` of this branch into the scratchpad; the Makefile recipes by hand (no `make`): derive, index, views, roles, evidence, smoke, demo, `uv sync`, check, client, eval, validate, bench | all exit 0; bootstrap 25 s; smoke and demo identical to the reference logs; 101/101; client PASS; 15/15; 13/13; bench 92 s | PASS |
  | Every number on a slide independently re-derived | `sql-verifier`, fresh SQL on the raw Parquet (views only where the claim is about a view), 17 claim groups | **17/17 MATCH**; one wording fix applied: the 3,638 belongs to ciod `… Link has been severed` (two other signatures share the CioStream prefix: 588 and 443) | PASS |
  | Slides | 13 slides, each footer names the command behind its figures | published; shared with Arnie is a click on Share | PASS |

## Decisions

- The team plan governs schedule, split and stage numbers; `docs/build-plan.md` is the design reference.
- To settle with Arnie: manager answers name affected components and owning teams (the brief asks for them), never raw log text. PLAN.md §7 already reads this way ("affected component family and owning team", never node IDs or logger names); the role views follow it.
- The probe creates objects only in `exhibit_probe`, never in `postgres` or `exhibit_scratch` (left for hand tests and `serenedb-expert`).
- Stage 3 ranking definitions (in `bgl_signature_stats`, used by `make demo`): blast radius = distinct nodes affected; persistence = distinct active days; both as dense ranks over the 100 alert signatures; the manager order is `rank_blast_radius + rank_persistence`, ties by blast radius then `signature_id`. It ranks measured factors and is labelled "not an impact estimate". Arnie's `rank_by` may choose differently; then the demo changes with it.
- Every ranking breaks ties on `signature_id` (or `instance_id`), so a rerun gives the same rows and the evidence hash holds.
- The label check sits in `make demo` as a separate "VALIDATION (outside the agent)" block, run as `postgres`; no role view or tool reads the labels. Stage 5 moves it into the ground-truth script.
- Trend for the lead is incidents per week (gap 5 min), not lines, with zero weeks filled by `generate_series` before `regr_slope`; "recent" anchors on the dataset's last week.

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
| Bootstrap (derive → index → views → roles) | 14.4 s wall clock, three identical rebuilds | `time ( docker exec -i serenedb psql … -f - < sql/10_derive.sql && … 20 … 30 … 50 )` | Sat 13:00 |
| `make demo` | 2.4 s, 243 lines, identical across runs and rebuilds | `docker exec -i serenedb psql -h 127.0.0.1 -p 7890 -U postgres -f - < sql/90_queries.sql` | Sat 13:00 |
| Stage 3 golden | 76 / 76 rows `t`, two runs | `tests/golden/stage3_numbers.sql` → `logs/golden-stage3.log` | Sat 12:58 |
| Ranking inversion | DTLB first by lines (152,734), 117 incidents, 12th by blast radius + persistence; `rts panic` first (3,394 nodes, 124 days) | `make demo` W1 E1, M2 | Sat 12:50 |
| BGL clock | `ts` = US Pacific wall clock (epoch − 7 h to 2005-10-30 01:18, − 8 h after); 49 rows in the repeated hour, 0 alerts | `docs/data-notes.md` | Sat 12:35 |
| Bootstrap on merged `main` | 17.8 s (derive 9.4, index 3.9, views 1.3, roles 2.2, evidence 0.6) | the five recipes through `docker exec -i serenedb psql … -v ON_ERROR_STOP=1` | Sat 16:12 |
| Fresh clone, Windows (Stage 6 gate) | bootstrap 25 s; smoke and demo identical to the reference logs; check 101/101 + stock client PASS; eval 15/15; validate 13/13; bench exit 0 in 92 s | `git clone` of `stage-6-adnan`, every Makefile recipe by hand (no `make` here), `PYTHONUTF8=1` | Sat 18:15 |
| Ground truth | 4/4 labelled at 1–4 of 2,069; BGL signature/label agreement 99.9998%, TP 348,454 FP 3 FN 6 | `make validate` (three identical runs) | Sat 16:25 |
| Remote OTel bench | 1 s: 536,041 rows indexed in 24.8–32.2 s, 14,676 KB; 10 s: 5,275,597 rows in 60.0 s, 136,472 KB; 30 s and 60 s: SIGSEGV | `make bench`, `make bench-ladder`, `BENCH_LADDER="30"` | Sat 18:05 |

## Background jobs

| Job | PID | Log | Started | Status |
| --- | --- | --- | --- | --- |
| | | | | |

## Handoffs to Arnie

- **Workspace indexes are back on the table (your optional `create_index` / `drop_index`).** On pattern B a partial inverted index restricts when named: `CREATE INDEX <name> ON bgl_ev USING inverted (id, content log_text, ts, …) WHERE <predicate>`, then `VACUUM (REFRESH_TABLE) bgl_ev`, then `FROM <name> WHERE content @@ …` returns only rows matching the predicate. The win is build time (about a fifth for a 9% window), not query time (about 0.4 ms). `sdb_indexes()` does not show the predicate, so the tool must record it. PLAN.md §14 item 4 and §16 still say "no effect"; yours to update. Details: `docs/capabilities.md` §3.
- `make probe` works again (`PSQL=… DATA=…` pass through); no change to your code.
- ✔ Done by Arnie (`bba98b3`). **The one-node burst number in PLAN.md is wrong: 152,183, not 136,209** (verified twice, `tests/golden/headline_numbers.sql`). PLAN.md is yours, so I have not touched it. Lines to change: 124 (table row: "2005-06-11 17:17 → 23:39 | 152,183 | 1"), 127 ("39%" → "44% of all alert lines … in under six and a half hours"), 308 (W1 engineer: "one node emitting 152,183 lines in 6h22m"), 497 (appendix). The comparison is stronger, not weaker: 152,183 lines on 1 node against 49,154 on 22,529. Fixed in my files: `CLAUDE.md`, README (also 18,770 → 19,250 episodes), `docs/build-plan.md` §0, `docs/data-notes.md`, `sql/99_smoke.sql`. Any slide or video script that has 136,209 or "5h43m" needs the same change.
- ✔ Done by Arnie (`98d5957`, persona-aware registry). **Roles are in the database now (`sql/50_roles.sql`); `datasets.py` needs the per-role relations.** Roles `exhibit_engineer`, `exhibit_lead`, `exhibit_manager` (the names in `.env.example`), no password, so connect as `postgres` and `SET ROLE` (a role cannot log in on its own; see the Stage 3 note below).
  - engineer: unchanged, everything you query today, including `bgl_idx` / `os_idx` by name.
  - lead: no per-line relation and **no full-text search** (the database refuses `bgl_idx`, because a search on an index is checked against `bgl_ev`). Use `lead_bgl_daily` (day, team, component, level, alert_category, is_alert, signature_id, signature, lines, nodes, midplanes), `lead_os_hourly` (hour, team, service, logger, level, signature_id, signature, lines, instances, requests, http_errors), `bgl_incident`, `bgl_signature_incidents`, `os_instance_durations`, `owner_map`. `search_logs` for the lead should return "not permitted for this role". `nodes` / `instances` / `requests` are distinct per bucket: never sum them.
  - manager: `mgr_bgl_risk` (signature_id, alert_category, component, team, worst_level, alert_lines, episodes_5min, nodes_affected, midplanes_affected, peak_nodes_per_episode, active_days, longest_episode, first/last_seen), `mgr_os_risk` (signature_id, service, team, worst_level, lines, instances_affected, requests_affected, active_hours, first/last_seen; above INFO only), `mgr_rollup_daily` (dataset, day, team, component, category, level, lines). A problem is named by `signature_id` + `alert_category` + component + team, never by text. The views carry factors only; the ranking by blast radius and persistence is your `top_signatures` `rank_by`.
  - New column `signature_id` on `bgl_sig`, `os_sig`, `bgl_incident`, `bgl_signature_incidents`: the join key between the lead's and the manager's views.
  - **Changed in item 4:** `mgr_os_risk` is now one row per *problem* (dataset, problem, service, team, worst_level, incidents_5min, records, tracebacks, lines, critical_lines, error_lines, warning_lines, requests_affected, first/last_seen), no longer per signature_id. New `mgr_os_lifecycle` (file_group, instances, spawned, spawn p50/p95/max, image p50/max, boot p50/max).
- **W2 views for your `episodes`, `durations` and `top_signatures` on OpenStack** (`sql/30_views.sql`): `os_problem_incidents` (one row per problem: episodes, records, tracebacks, lines by level, team), `os_incident` (one row per incident), `os_episode` (per line, engineer only), `os_instance_durations` (now with claim_s, image_s, boot_s, run_s, teardown_s, destroy_s, dealloc_s, lifetime_s, source_file, and the real owning team), `os_latency_by_file` (mean, p50, p95, p99 per file and per normal/abnormal group). `os_sig` adds `level_rank`, `record_key`, `problem`, `event`, `took_s`. The OpenStack episodes gap is fixed at 5 minutes in the view, as for BGL; if `episodes` must take 1/5/60 on OpenStack too, the tool needs the parameterised SQL pattern rather than the view.
- ✔ Done by Arnie (PLAN.md §4, §9, §17 now read this way). **PLAN.md OpenStack wording (yours to change; numbers verified, `tests/golden/w2_numbers.sql`):** §17 "188 error lines = 8 tracebacks of one bug + 6 CRITICAL auth lines" is wrong (184 + 6 = 190, and only 2 lines are CRITICAL). Suggested: "188 ERROR + CRITICAL lines = 184 lines in 8 tracebacks of one imagecache bug + 4 token-validation lines (2 failed validations, 6 lines with their 2 WARNINGs)". §4 "188 error lines ≈ 8 incidents of 1 bug" has the same problem, and "184 ERROR lines, all from `nova.virt.libvirt.imagecache`" should say *logged by `oslo_service.periodic_task`*, with imagecache in the stack frames. §9 W2 manager "six lines of CRITICAL auth failures" → "2 CRITICAL token-validation failures (6 lines)". `docs/build-plan.md` §0 says "6 CRITICAL auth lines" too; I fix that one.
- **Ownership trap worth a demo line:** the imagecache traceback is logged by `oslo_service.periodic_task`, so logger-first precedence gives it to `platform-services`, while the imagecache warnings go to `image-service`. One bug, two teams. Your lead answer should say so; changing `data/ownership.csv` is our call together.
  - Your evidence ledger: every role needs `SELECT` / `INSERT` on `exhibit_evidence` once it exists. Add the grants to `sql/50_roles.sql` (one table per GRANT statement) or tell me the table name and I will.
  - `make bootstrap` now runs `roles` last; `sql/30_views.sql`'s `DROP … CASCADE` removes the role views, so never run views without roles after it.
- **Stage 3: which relation backs which tool** (all in `sql/30_views.sql` / `sql/50_roles.sql`; `make demo` runs each one, labelled with the tool name; the numbers to match are in `logs/demo-pass3.log`):

  | Tool | Engineer / lead | Manager | Order or parameter |
  | --- | --- | --- | --- |
  | `top_signatures` BGL | `bgl_signature_stats` (signature text, `top_node`) | `mgr_bgl_risk` (no text, no node ID; adds `top_node_pct`, `rank_blast_radius`, `rank_persistence`) | lines → `alert_lines DESC`; episodes → `episodes_5min DESC`; nodes → `nodes_affected DESC`; blast radius → `rank_blast_radius`; persistence → `rank_persistence`; risk → `rank_blast_radius + rank_persistence, rank_blast_radius, signature_id`. Always end with `signature_id` for a stable order |
  | `top_signatures` OpenStack | `os_problem_incidents` | `mgr_os_risk` | `critical_lines DESC, error_lines DESC, incidents DESC` |
  | `episodes` | `bgl_episode_sensitivity` (1 / 5 / 60 min, per midplane and global), `bgl_incident` (5 min rows) | `mgr_bgl_risk.episodes_5min` | any other gap or scope: the pattern below |
  | `trend` | `lead_bgl_daily`, `lead_os_hourly` (lines); `bgl_incident.started` (incidents) | `mgr_rollup_daily` | weekly slope: `make demo` W1 L4 (zero weeks via `generate_series`, then `regr_slope`) |
  | `durations` | `os_instance_durations` (rank `spawn_s DESC NULLS LAST, instance_id`), `os_latency_by_file` (`source_file = 'ALL'` = per group) | `mgr_os_lifecycle` | — |
  | `ownership` | `ownership_coverage`, `owner_map` | `ownership_coverage` (granted: teams and counts only) | `matched_on` = the key that assigned the team; OpenStack teams can span two rows, sum them |

  **Parameterised episodes** (a gap or scope the view does not hold), tested with literal values: DTLB 132 / 117 / 57 at 60 / 300 / 3,600 s per midplane, 553 / 553 / 545 per node:
  `WITH d AS (SELECT ts - LAG(ts) OVER (PARTITION BY signature, <scope column from datasets.py> ORDER BY ts) AS gap FROM bgl_sig WHERE is_alert AND signature = %s) SELECT count(*) FILTER (WHERE gap IS NULL OR gap > %s * INTERVAL '1 second') FROM d` (gap in seconds as an int). Not tested through psycopg's binding from this box (host connections need a password, below): check that the bound int multiplies an INTERVAL without a cast error, as `ts_any` needed `::TSQUERY[]`.
- **The engineer relation in `datasets.py` ranks BGL by the label.** `src/exhibit/datasets.py:141` maps group `signature` to `alert_category` on `bgl_ev`, so the engineer's `count_events(group_by="signature")` groups by label, which CLAUDE.md rules out (84,253 ASSERT lines sit under `-`); `:163` maps it to `logger` on `os_ev`. The lead and manager relations already use the real `signature`. Suggest calling the engineer group `category`, and serving the engineer's signatures from `bgl_signature_stats` (granted to the engineer) and OpenStack problems from `os_sig.problem` / `os_problem_incidents`.
- **Your `SET ROLE` design is the only one that works** (measured, `docs/capabilities.md` §6): a LOGIN role without a password is refused even over the container's loopback (`password authentication failed for user "exhibit_lead"`); SereneDB trusts only `postgres`, on loopback. `db.py:86` already does it; nothing to change. Giving the roles passwords would be a joint decision.
- **`mgr_bgl_risk` gained columns** (`top_node_pct`, `rank_blast_radius`, `rank_persistence`); none removed or renamed, so your manager relation's column list still works. Add them if `top_signatures` should rank by blast radius or persistence for the manager.
- **From the Windows host, `postgres` needs a password too**: Docker Desktop forwards `127.0.0.1:7890` from the bridge, which the default HBA treats as remote (`password authentication failed for user "postgres"`). Your server will fail on my box until we pick one: `POSTGRES_PASSWORD` on first start, `ALTER ROLE postgres PASSWORD …` (with `SERENEDB_PASSWORD` from `.env`), or `SET hba` trusting the bridge. Security setting, not changed by me.
- **PLAN.md §9 W1 lead (line 316) is still wrong (yours; verified, `tests/golden/stage3_numbers.sql`)**: "91% of alert volume belongs to `compute-platform`" → "91% of all BGL lines, but 82% of alert lines and 52% of incidents; workload-runtime (ciod) has 48% of incidents". "thousands of small incidents across eight nodes" → "thousands of small incidents, each touching at most 8 nodes (1,024 I/O nodes overall)". W1 manager: the ranked list exists now, and DTLB, first by lines, is 12th (`rts panic`, 3,394 nodes on 124 days, is first). §8 "132 / 117 / 57" is right. New for W1 lead: by weekly trend, Lustre's incidents are all in 3 weeks and none in the last 9; ciod's 3,638 are all in the last 9 (slope +14.8 a week).
- **`statement_timeout` is not enforced by the server** (it warns and runs on). Rule 9's 30 s limit on tool paths has to be enforced in your code: e.g. a timer that calls `conn.cancel()`, or run the query in a thread and cancel on timeout. Do not rely on `SET statement_timeout`.

## Open issues

- README's `APPSEV` "7,036 episodes" is per **alert category** × midplane, not per signature like the rest of that paragraph (now labelled; checked: 7,036 by category × midplane, 7,165 summed over its 5 signatures).
- On a search table the partial-index "rows outside" count came out 87,443 in the probe and 87,442 by hand (the complement is 87,442). Pattern A only, not used; recorded, not chased.

- ✔ Fixed by Arnie (round 2): the Makefile's psql targets read `< sql/…`, so `PSQL='docker exec -i serenedb psql …'` works.
- ✔ Resolved (item 5): `make check` / `make eval` now run from this box (101/101, 15/15) since the container has `SERENEDB_HOST_AUTH_METHOD=trust`.
- No `make` on this Windows box: every gate here ran the Makefile recipes through `docker exec -i serenedb psql -h 127.0.0.1 -p 7890 -U postgres` with the file on stdin, and `MSYS_NO_PATHCONV=1` (Git Bash otherwise rewrites `/data/...`).
- Remote index ceiling (item 7): 30 s and 60 s slices of the OTel file crash 26.09.1.3 on this box during `CREATE INDEX`; 10 s works. Not chased further: worth one try on Arnie's arm64 box (12 GB) before the video, if the bonus slide should show a bigger slice.
- The SereneDB crash (SIGSEGV, PC `0x27fb407`) is reproducible from `docs/capabilities.md` §11; reporting it to the SereneDB team is a decision for both of us (it is outward-facing).

## Next

- Stage 7 (video, Sun 15:00–19:00): the deck's speaker notes are a first script; every on-screen number has its command in the slide footer and in `docs/slides.md`.
- Arnie: round 4 handoff below (the `.mcp.json` exhibit entry is the one with judging impact).
- Both: share the deck with Arnie, export it to PDF for submission; star SereneDB on GitHub (a listed prerequisite, a click each).

## Handoff back (Arnie, Stage 3, Sat 17 Oct)

Branch **`stage-3-tools`**, PR open, **not merged** — I am holding it until you finish so we do the
final consensus together. Nothing of yours is touched: `sql/50_roles.sql`, `tests/golden/`, the
W2 views and `CLAUDE.md` are exactly as you left them.

- **All ten tools exist now**, plus `verify_evidence` = eleven. `make check` runs **85 checks**
  (was 46) and `scripts/stage2_mcp_client.py` exercises Stage 3 through a stock MCP client too. The
  new checks assert numbers, not shapes: `episodes` must return 19,250 at a 5-minute gap and equal
  the prebuilt view it recomputes; `top_signatures` ranked by lines / nodes / episodes must return
  **three different** top problems, and it does.
- **The evidence ledger is mine to wire, and it is done**: table `exhibit_evidence`, created by
  **`sql/55_evidence.sql`** (`make evidence`, which `make bootstrap` now runs *after* `roles` —
  your GRANTs are reset by that file, which is why 55 must come last). You do **not** need to add
  anything to `sql/50_roles.sql`; I granted the three roles SELECT/INSERT there, one table per
  statement as you said. Every answer — **including every refusal** — is recorded, and
  `verify_evidence` re-runs a stored statement and compares hashes.
- **PLAN.md is updated** for everything you flagged: the burst, the OpenStack wording (§4/§9), the
  team name. One thing to know so nobody "fixes" it later: **both burst numbers are right and they
  are different cuts.** 152,183 = every alert line on that node that day (152,182 `KERNDTLB` + 1
  `KERNMC` at 17:17:44.605); 152,182 = the single incident `episodes` reports. PLAN.md §4 now says
  so, and the acceptance suite guards both.
- **One measured deviation from the plan, recorded rather than fudged:** `what_changed` was
  specified with `ts_dict_agg` / `ts_dict_count`. `ts_dict_agg(content)` returns per-term *identifier
  arrays* — one call over ~21k lines returned about **4.8 MB** — and `ts_dict_count` takes exactly one
  argument and returns `INTEGER[]`, so neither gives a bounded term→count map and neither can be
  paired with terms. Change is therefore measured at **signature** level, rate-normalised per bucket
  (a 6-hour window against 24 hours must not read as "down 75%"). PLAN.md §7 and
  `docs/capabilities.md` §8 carry the measurement.
- **Your `episodes`-gap note was exactly right and it shaped the design.** The engineer holds a grant
  on `bgl_sig` / `os_sig`, so the gap is a real bound parameter (`INTERVAL '1 minute' * %s` binds);
  the lead and manager read pre-grouped relations, so asking them for another gap returns a refusal
  that names the reason instead of silently returning a different number. `docs/capabilities.md` §8
  also records that `date_bin` here is **3-argument** (stride, source, **origin**), which is why
  buckets align to each corpus's own start.
- **You wrote `sql/90_queries.sql` while this was open** — I rebased onto it and ran `make demo`;
  it prints W1 and W2 as intended, and my tools print the same numbers from the other side. When
  you run my Stage 3 tools against `logs/demo-pass3.log`, `episodes` should give 19,250 at a
  5-minute gap and 152,182 lines for the worst incident, and `top_signatures by=nodes` should put
  `Microloader Assertion` on top — those three are acceptance checks, so a mismatch means the
  data moved, not that the tool drifted.

## Handoff back, round 2 — after your Stage 3 landed (Arnie, Sat 17 Oct)

Your half is on `main` at `814f1f3`; my branch is rebased on top of it, `make check` is **94/94**,
and `make demo` prints your W1/W2 unchanged. **I verified every number you quoted, with my own SQL
and through my own tools, before believing any of it.** Results, including the two places your
message was loose:

- **91% / 81.61% / 52% / 48% — confirmed.** `compute-platform`: 4,325,112 of 4,747,963 all lines
  (91.1%), 284,391 of 348,460 alert lines (81.6%), 9,952 of 19,250 incidents (51.7%); ciod 9,258
  (48.1%). All four now sit in PLAN.md §9 W1 with the cut labelled on each.
- **"eight nodes" — you are right and I was loose.** `max(nodes)` in any one Lustre incident is
  **8**; the signature reaches **1,024 nodes** overall. PLAN.md now says "at most 8 nodes in any one
  of them, 1,024 I/O nodes overall" rather than my earlier "eight per midplane".
- **DTLB 152,734 / 99.64% one node — confirmed** (152,182 of 152,734).
- **rts panic: 3,394 nodes, 124 days — confirmed** (`KERNRTSP`). But the phrasing in your message
  conflated two measures, so PLAN.md now separates them: DTLB is **12th by blast radius** and **23rd
  by blast radius + persistence**, and rts panic is **1st on the combined measure**. By peak blast
  radius *alone* the top is a third signature (the fleet event, 22,529 nodes) — worth knowing before
  a judge asks which ranking you mean.
- **132 / 117 / 57 — confirmed twice.** Once as your literal SQL, once through my tool with a bound
  parameter: `episodes(bgl, engineer, gap_minutes=1|5|60, signature='data TLB error interrupt')`
  returns 132 / 117 / 57. So the answer to your "not tested through psycopg's binding" note is: it
  binds, it works, and it is now an acceptance check rather than a claim.
- **ciod 3,638 all in the last 9 weeks, Lustre none — confirmed** (`Lustre mount FAILED : bglio{n} :
  point /p/gb{n}` = 3,667 incidents, last one 2005-09-16; ciod's 3,638 run 2005-11-17 → 2006-01-03).
  That contrast is now in PLAN.md §9 as the lead's answer.

What I changed because of your handoff:

1. **`datasets.py:141` — fixed, and your reasoning was right.** The engineer read `bgl_ev`, whose
   `signature` group was `alert_category` (the label). The engineer now reads **`bgl_sig` / `os_sig`**
   — same rows, masked signature added — so `group_by="signature"` means a signature, and the label
   has its own `category` group. Measured, as the check: `category` puts **4,399,503 of 4,747,963
   lines under `-`**, `signature` puts `generating core.{n}` on top. Two calls, and the trap is
   visible in the demo.
2. **`episodes` gained `signature=`** (which is how I reproduced your 132/117/57 above). It is
   **refused for the manager**, whose relation names problems by `signature_id` and not by text —
   the refusal says so and points at the key.
3. **The password question — answered, and the answer is one flag, not a decision about secrets.**
   It is not a security setting we have to trade off: the container's `/entrypoint.sh` writes its HBA
   **only if `SERENEDB_HOST_AUTH_METHOD` is set**, and without it the default trusts `postgres` on the
   container's own loopback and demands a password from anywhere else — including Docker Desktop's
   forwarded loopback, which the container sees as remote. So: `-e SERENEDB_HOST_AUTH_METHOD=trust`
   on the container (recognised values: `trust | reject | password | md5 | scram-sha-256`; **any
   other value logs a parse error and silently falls back to demanding a password**). It is
   documented in the README's docker run with the scope warning. My box already runs with it, so
   `psql -h 100.108.122.19 -p 7890 -U postgres` should work from your machine as it stands — I
   verified a connection over the Tailscale address with no password. Nothing for us to choose: the
   roles stay passwordless and we keep `SET ROLE`, which you and I both measured is the only path
   that works.
4. **Makefile `-f sql/x.sql` → `< sql/x.sql` — done** (your Stage 6 item; `make smoke`, `make demo`
   re-run afterwards).
5. **The ledger grants stay in `sql/55_evidence.sql`.** Don't add them to `sql/50_roles.sql`: 50 is
   yours, 55 is mine, and separate files mean we never collide. `make bootstrap: derive index views
   roles evidence` — 55 after 50, because 50 resets grants.

Two more failures worth your time, both at the MCP boundary rather than inside a tool:

- **The server forwarded arguments positionally.** Inserting one parameter into a tool's signature
  shifted every later argument: `episodes(..., limit=3)` arrived as `signature=3` and the server
  answered `Could not convert string 'rts panic! - stopping execution' to INT16 ... WHERE signature
  = $2`. Every unit-level check passed — the function was called correctly in all of them and
  incorrectly by its only real caller. All wrappers forward by keyword now, and the stock-client
  check exercises the tools over MCP, which is the only place that bug is visible.
- **The manager's ranked list was not JSON-serialisable.** This engine returns DECIMAL for
  `sum(...)`, `date` for a bucketed day, `datetime` for a timestamp and `timedelta` for a duration;
  `json.dumps` takes none of them, and
  **7 of 10 sampled tool calls raised `TypeError` on a strict client while 93 acceptance checks stayed
green** — they compare Python objects, and the MCP layer's pydantic models were absorbing the rest.
Everything now normalises in the shared envelope, and there is a check that dumps every tool for
every persona. One knock-on: once the envelope normalised, `verify_evidence` started reporting
MISMATCH on identical answers (the recorded rows were normalised, the re-run rows were raw), so the
ledger's hash now canonicalises both forms. If you run my tools over MCP, those are the fixes you
are picking up.

Also added while I was in there, because the demo quotes it: `episodes` takes **`signature=`** and
`scripts/stage2_mcp_client.py` asserts **117** incidents for `data TLB error interrupt` at a
5-minute gap — your number, through my tool, over MCP, as part of `make check`.

---

## Handoff back, round 3 — the lints, the eval, and three seam fixes (Arnie, Sat 17 Oct)

> **Update, 14:0x UTC:** PR #3 is **merged** into `main` at Arnie's instruction (`main` = `116c4e5`;
> rebase, no rewrites). Verified from a fresh clone of merged `main`: **101/101 checks, stock client
> PASS, `make eval` 15/15**. The review points below stand for reading — and the Q&A tonight is
> where we close the loop on them. See also the new **Status column in `PLAN.md` §11**.

**First, what happened to your half:** PR #2 was merged into `main` at 12:21 UTC today (rebase; your
Stage 3 is the base of it). `main` = `0fe49f6`, and a clean clone of `main` passes 94/94 + the stock
client. Nothing of yours was rewritten; the `PROGRESS.md` conflict was the only overlap.

**Then this branch (`stage5-eval-and-lints`, PR #3) — four things, all on the seam between our two
halves, which is where the bugs were:**

1. **The answer lints are now code, not prose** (`src/exhibit/lint.py`, MCP tool `lint_answer`).
   The manager lint rejects money / `downtime` / `customers` / `revenue` / `SLA` in a manager
   answer, and *allows all five inside quotes* — the rule bans claiming, not quoting. The numeric
   lint requires every figure in the Observed block to cite an id that resolves, and with
   `deep=true` it re-runs the statement and checks the figure against the result, its aggregates
   (sum / min / max / row count) and the total the envelope reported. Measured now: 101/101 checks,
   including through the stock MCP client.
2. **`evals/` is no longer an empty promise** — `make eval` runs 15 questions, three roles, every
   figure compared against hand-written SQL in `evals/golden.sql` (not the SQL the tools build), and
   each answer goes through the lints before it counts. **15/15, 19 figures, 6 refusal assertions.**
   The three negative questions are yours in spirit: `durations(manager)` must be refused with
   `spawn_s` named, `trend(lead, bucket="week")` must tell the caller to ask for `day`, and
   `ownership(manager)` must name the missing grant.
3. **Two of your tools' ids did not resolve** — `search_logs`, `count_events` and `describe_data`
   handed out evidence ids without recording them, so an answer citing them could not be verified
   at all. They record now. And `verify_evidence` used to *raise* on a refusal's id ("the last
   operation didn't produce records"); it now reports `REFUSAL — nothing to re-run`, which matters
   because your refusals are recorded as answers.
4. **`sql/55_evidence.sql` gained a column** — `total_matches BIGINT`, with an idempotent
   `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` so `make evidence` is safe to re-run on a database
   that already has the table. I applied it to the live one. If you re-run `make bootstrap`,
   nothing changes; if you re-run only `make evidence`, the ALTER carries it.

**Small items while you were away:**

* `logs/demo-pass3.log` is gitignored, so the numbers you asked me to match against are not in the
  repo. I matched them anyway from the live database (117 at a 5-minute gap for `data TLB error
  interrupt`, 132/117/57 at 1/5/60 minutes) and they are now *checks*, so the comparison cannot go
  stale. If you want the file itself in the repo, `git add -f logs/demo-pass3.log` — your call.
* `make bench` runs `sql/70_bench.sql`, which does not exist, so that target fails in a clean
  checkout. Yours (bonus ladder §14); either write it or I will have the target say it is not
  implemented yet.
* **`make derive` was broken on a clean clone and nobody could have seen it**: `DATA` and `MAP`
  carried trailing whitespace because the comments sat on the assignment lines
  (`DATA ?= /data/loghub   # ...` — in Make, the whitespace before a trailing `#` is part of the
  value). `make derive` therefore asked for `/data/ownership.csv   ` and the glob matched nothing.
  Every target I had verified on a clone — `setup`, `check`, `eval` — skips derive, so the gate that
  catches it is the full sequence: **`make clean-check` now passes end to end** ("clean checkout
  OK"), and the fix is in this branch. If your own `make bootstrap` has been working, it is because
  your checkout has the same padded value *and* a `data/ownership.csv` path that tolerates it — run
  `make clean-check` once to be sure.
* `docs/disclosure.md` now exists (the rules require disclosing models, tools and datasets, and the
  README pointed at a file that was not there). It states plainly which assistant wrote which lane —
  an Anthropic Claude assistant for yours, Hermes for mine — and that no model runs in the answer path.

**What I would do next, in order:** nothing is blocking the submission.
(1) `make demo` + `make eval` on the merged branch, and the 5-minute video;
(2) the three answers for the Q&A in PLAN §13 that measurement has now settled — the brief's
"twelve categories" (BGL has 42), "five severity levels" (we measure six), and the 3-vs-5-minute
demo question;
(3) if there is time on Sunday, the bonus ladder (§14) — the bench target is the only broken one.

---

## Handoff to Arnie, round 4 — audit of merged `main`, Stage 5's missing script, the bench, the slides (Adnan, Sat 17 Oct)

Branch **`stage-6-adnan`**, not pushed. I ran your list in order: pulled `dbddf95`, read round 3,
ran `make demo` and `make eval` from Windows (both green once the container had the auth flag:
**101/101, stock client PASS, eval 15/15**), and did not reopen anything in your "already settled"
list. The W2 split holds (184 ERROR → platform-services, 3,059 warnings → image-service).

**What this branch adds (all mine unless marked):**

1. **`scripts/validate_ground_truth.py` did not exist.** PLAN §7 and §11, `docs/disclosure.md` and
   `evals/golden.sql` all cite it; it was never committed. It exists now (`make validate`, 13/13,
   `docs/validation.md`). PLAN §11's Stage 5 row ("ground truth was already in") is now true; it was
   not when written.
2. **`make bench` works** (`sql/70_bench.sql`, `bench/run_ladder.sh`, `bench/README.md`,
   `docs/capabilities.md` §11). The one fact everyone touching remote Parquet needs:
   **`SET enable_external_file_cache = false` before any remote read.** With the default (on), a
   time-filtered read is not pruned and big reads kill the server (SIGSEGV, same PC, every time).
   With it off, a slice of the 1B-row file is pruned to its row groups and an index on a view over it
   builds and searches. Ceiling on my box: 10 s of data (5,275,597 rows) indexes in 60 s; 30 s and
   60 s of data crash the build. Also: filter on `"TimestampTime"`, never `"Timestamp"` (ns).
3. **Makefile** (shared, small): `up` passes `-e SERENEDB_HOST_AUTH_METHOD=trust` (README had it, the
   target did not); `export PYTHONUTF8 := 1` (your checks print `✓`, which a Windows console cannot
   encode); targets `validate`, `bench` (`BENCH_SECONDS`), `bench-ladder`.
4. **`LICENSE`** (MIT; README said MIT, there was no file), README fixes (101 checks, 12 tools,
   repo map, Windows note), `docs/capabilities.md` §4 and §11.
5. **The slide deck** (team plan Stage 6's open item): 13 slides, every number with its source
   command in the footer, private until we share it. Link in chat; speaker notes on each slide.

**In your files — found, not edited (your call each):**

- `src/exhibit/analytics.py:524` — `durations` orders `ORDER BY {phase} DESC LIMIT %s` with no
  tie-breaker. `os_instance_durations` has 292 distinct `spawn_s` values over 2,066 instances (ties
  from position 9 on: 21.85 ×2), so tied rows can swap between runs and a stored hash can stop
  matching. Suggest `ORDER BY {phase} DESC NULLS LAST, {src.key}`. (`NULLS LAST` is this engine's
  default even under `DESC`, unlike PostgreSQL; writing it keeps the statement portable.)
- `scripts/stage2_mcp_client.py:46` — `expected` lists 11 tools; `lint_answer` is the 12th and is
  not asserted, so the client prints "all 11 tools are exposed" while 12 are.
- **`.mcp.json` registers only `serenedb-docs`, not exhibit itself.** A judge whose MCP client reads the
  repo's `.mcp.json` gets no exhibit tools until they add the server by hand. For the MCP-server award:
  `"exhibit": {"command": "uv", "args": ["run", "exhibit-mcp"]}` (packaging is yours).
- `PLAN.md:348` — "12th by blast radius and 23rd by blast radius + persistence": 23 is DTLB's rank
  **sum** (blast radius 12 + persistence 11); its **position** on the combined measure is also 12th
  (`make demo` W1 M2, `risk_position` 12). Suggest "12th by blast radius and 12th on the combined
  measure (rank sum 23)". `PLAN.md:274` still says 80 checks (101 now).
- `evals/golden.sql:6` — attributes "76 of 76 checks" to `scripts/validate_ground_truth.py`; those
  76 are `tests/golden/stage3_numbers.sql`. The validation script runs 13 expectations.
- `docs/disclosure.md:67` — "Both were raised with the challenge owners at the Q&A" was written
  before the Q&A; and "the brief's 44% figure was ours to correct" reads as if 44% were the brief's
  error, while 44% is our measured figure (our earlier 39% was the wrong one). Line 42 says "his
  views"; "those views" avoids guessing pronouns.
- `src/exhibit/server.py` — `verify_evidence` raises an unhandled `UndefinedTable` when the ledger
  table is missing (a database bootstrapped before `sql/55_evidence.sql`); a refusal-style message
  would be friendlier. Only seen on my stale database.

**Not done, deliberately:** nothing pushed; no edits to your files; PLAN.md untouched (§9, §11,
§14 item 3 and the bench result are yours to fold in, with the numbers above).

## Handoff back, round 5 — your seven findings, fixed (Arnie, Sat 17 Oct, late)

All seven, merged as PR #6, with `make check` 101/101 (stock client PASS) and `make eval` 15/15:

- **`durations` tie-breaker** — now `ORDER BY {phase} DESC NULLS LAST, {src.key}`; two runs return
  identical order, and a stored durations entry (E-06B068) still verifies MATCH, because the rows
  hash is order-independent. Your NULLS LAST note is in the code as a comment.
- **stock client** asserts the 12th tool now; it prints "all 12 tools are exposed".
- **`.mcp.json`** registers `exhibit` itself — `uv run exhibit-mcp` (your suggested shape,
  verbatim); verified to start on stdio. The other connection paths in §14 item 1 stay open.
- **PLAN.md** — rank wording now "12th by blast radius and also 12th on the combined measure
  (rank sum 23)"; 80 → 101 checks; Stage 5's "ground truth was already in" rewritten to the truth
  (you committed the script — my round-3 wording was wrong; caught, fixed); Stage 6 status; §14
  items 1–3 marked, item 3 carries your bench numbers.
- **`evals/golden.sql`** — the 76 checks are `tests/golden/stage3_numbers.sql`; the validation
  script's 13 expectations are named separately.
- **`docs/disclosure.md`** — the Q&A outcome is recorded (the owners: the data is authoritative;
  full measured sets, no mapping); "those views"; 44% phrased as ours, with (152,183 of 348,460).
- **`verify_evidence`** — a ledgeless database now gets a NO LEDGER refusal naming
  `sql/55_evidence.sql` / `make evidence`, instead of an `UndefinedTable` raise.

**Your two "both of us" items:**

1. **Bigger bench slice on the arm64 box** (30 s / 60 s) — ready to try before the video if the
   bonus slide wants it; the ceiling gets reported either way.
2. **The SIGSEGV report** — proposed as one line in the organisers' follow-up
   (`docs/followup-questions.md`): reproducible from `docs/capabilities.md` §11, trigger is the
   `enable_external_file_cache` default, workaround off. Say if you would rather keep it in-repo.

## Handoff back, round 6 — a live demo endpoint (Arnie, Sun 18 Oct)

The MCP server now also speaks **streamable HTTP**, so the system runs as a live demo endpoint —
a judge (or you) can point an MCP client at it without cloning anything:

- `https://hermes.bushbaby-platy.ts.net:10000/mcp` (streamable HTTP; read-only; same three
  database roles; the `persona` argument still picks the role)
- locally: `make mcp-http` → `127.0.0.1:8900/mcp`
- runs under systemd on the box (`exhibit-mcp-http.service`, enabled, restarts on boot);
  the switch is `EXHIBIT_MCP_TRANSPORT=streamable-http`. `make check` still passes (stdio path
  unchanged). README §"Live demo endpoint"; `.mcp.json` carries an `exhibit-demo` entry so a
  client that reads the repo gets the remote one with zero setup.

**Update (Sun 15:00):** Funnel is enabled and the endpoint is **live and verified from the public
internet** — four independent nodes (check-host.net: AT/DE/PL/PT) reach it, and a full MCP handshake
through the public URL (initialize → 12 tools → a real call with an evidence id) works.
One fix on the way (PR #8): the MCP SDK's localhost guard was returning 421 for the public
hostname; the server now keeps the guard but allows the endpoint's own names. Unknown Host headers
still get 421.

**What is genuinely left for the submission:** (1) **the deck** — export it (PDF/PPTX) and
commit it (yours; the artifact is in your account); (2) **the video** — record it against
`docs/video-script.md`; (3) **stage 8** — flip the repo public and upload (§15). Nothing else is
open.

## Handoff back, round 7 — the endpoint's first real users, and three failures fixed (Arnie, Sun 18 Oct)

The live endpoint got real external traffic today (a local client from outside the tailnet, ~60
calls — the judges' path). Three calls failed; all three are now explained and addressed:

1. **`top_signatures(by="nodes")` as the manager on OpenStack crashed** (two of the three):
   `UndefinedColumn: "nodes"`. That relation renames its blast-radius column (`requests_affected`
   counts requests, not machines) and the ORDER BY used the logical name. Fixed — it now returns
   its ranking like every sibling (the engineer/lead combinations still refuse with the measured
   `nodes_unmeasurable` reason).
2. **`count_events` with a `group_by` that is not a bucket** ("nodes", "teams") died with an opaque
   error; now a refusal envelope listing the buckets the view actually has — same shape as a bad
   `by` on top_signatures.
3. **`since`/`until` with a non-ISO string** now reads "…use an ISO one like '2005-06-11'" instead
   of a bare crash; same for a bad search `mode`.

The client's third failure left no server trace — that class is the MCP SDK's own argument
validation (a missing required field or a wrong type), rejected before our code runs; the model
sees the field-level message and retries, which is exactly what happened.

`make check` 101/101, `make eval` 15/15, `make validate` 13/13 all still hold after the fixes.

