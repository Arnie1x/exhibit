# PROGRESS — Adnan's lane

Deadline: Sun 18 Oct, 23:59 · Current team stage: 0–1 (re-checked on a second machine) · Status: two-hour list in progress

## Stage log (team plan §11)

| Team stage | Window | Adnan's part | Result |
| --- | --- | --- | --- |
| 0–1 Probe, data layer | Done by Sat 12:00 | Re-probe, verify headline numbers, port `sql/50_roles.sql`, extend `os_sig` | |
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
- **Item 1, probe (Sat 17 Oct, 11:50–12:40).** `scripts/probe_capabilities.sh` rewritten against `bgl_ev`/`bgl_idx`/`os_ev`/`os_idx` (it queried the old `bgl`/`openstack` tables), 90 rows each with the outcome `docs/capabilities.md` claims, DRIFT on any difference, its own `exhibit_probe` database (recreated, dropped), idempotent (two runs identical). `make probe` pointed at it (it named a non-existent `sql/00_probe.sql`). **Broke one row**: the partial inverted index restricts on pattern B; the old "no effect" measurement was on a search table. Dictionary row holds. `docs/capabilities.md` §1, §2, §3, §7, §8 updated with the statements and results.

  | Acceptance (item 1) | Result |
  | --- | --- |
  | `make probe` runs on the current schema | 90 rows, 0 drift, exit 0, ~85 s |
  | Partial-index row re-measured, statements recorded | **Corrected**: `p_part` named → 34,056 = full index + window; 0 rows outside; holds when built before the load, after an UPDATE (34,057), and for an empty predicate (0). Ignored only on a `storage = 'search'` table (121,498) |
  | Dictionary row re-measured | **Holds**: `AS split_text(…)` → `syntax error at or near "AS"`; parenthesised `template = 'text'` form PASS; all five §5 lexize outputs identical |
  | Idempotent | two consecutive runs identical apart from timings; no `probe_*` role or database left behind |

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
| Headline numbers | 348,460 → 19,250 (5 min, signature × midplane) → 1,377 (signature); 136,209 lines on 1 node 2005-06-11 17:17:44 → 22:59:59 | `sql/99_smoke.sql` | Sat 11:49 |
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

## Open issues

- `sql/99_smoke.sql` §4b prints 136,209 / 49,154 / 22,529 as **literals**, not query results. The computed versions are §4 and §5 of the same file. Replace 4b with a computed query before anything quotes it (team plan §12 rule 4).
- On a search table the partial-index "rows outside" count came out 87,443 in the probe and 87,442 by hand (the complement is 87,442). Pattern A only, not used; recorded, not chased.

## Next

- Paste the first prompt from KICKOFF.md.
