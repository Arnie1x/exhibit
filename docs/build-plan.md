# Exhibit — 48-Hour Build Plan (SereneDB Log Challenge)

Oct 16, 2026 · @adnan

## 0. Team alignment: read this first

Arnie's team plan ("Logging off Early", 17 Oct 10:30) is now the operating plan: its schedule, work split, stage numbers and measured numbers win wherever they differ from this doc. This doc stays the design reference for tool contracts, evidence, verification and SQL patterns, and the measured corrections below are already applied to it.

**Where the build stands.** Stages 0–1 are done on the team box (SereneDB 26.09.1.3, arm64, 2 vCPU, 12 GB): `scripts/parse.py` turns the Zenodo files into Parquet, then `sql/10_derive.sql`, `sql/20_indexes.sql` and `sql/30_views.sql` build `bgl_ev`, `os_ev`, `owner_map`, `bgl_idx`, `os_idx`, signatures and episodes. `make bootstrap` rebuilds everything in about 20 s and `make smoke` prints the headline numbers. Do not rebuild Stages 0–1 from this doc; use their acceptance lists only to check `docs/capabilities.md` and `docs/data-notes.md`.

**Measured on the instance: these replace this doc's assumptions**

| Topic | This doc assumed | Measured (team plan) |
| --- | --- | --- |
| Dictionary DDL | `AS split_text(case := 'lower') WITH (…)` | Parenthesised form only: `CREATE TEXT SEARCH DICTIONARY log_text (template = 'text', locale = 'en_US.UTF-8', case = 'lower', stemming = false, accent = false, frequency = true, position = true)`; the `AS` form is a syntax error on 26.09.1.3 |
| Index size | `sdb_metrics` reports `num_docs` and `index_size` | No size metric anywhere (`sdb_metrics` holds connection, refresh and compaction counters; `relpages = 0`): measure wall-clock and the data directory |
| Partial inverted index | Basis of workspace indexes | No measurable effect: the planner does not pick it, counts ignore its predicate, timings equal (4.19 vs 3.99 ms) |
| BGL label | `-` means healthy; recurrence ranked on the label | 84,253 `-` lines carry an ASSERT fault (about 24% undercount): rank message signatures, not the label |
| Row counts | OpenStack 207,820 | 207,812 after parsing (8 lines lost, documented); BGL 4,747,963 of 4,747,963 |
| `template_id` | A masked-message key | Stays `'UNKNOWN'` (none supplied); the masked signature lives in the views |
| Text counts | `LIKE` cross-checks a count | Never support a count with `LIKE`: `@@ 'base'` gives 21,212, `ILIKE` 45,351; always state the operator |
| Types and highlights | — | Timestamps arrive as `VARCHAR`, so cast them; `date_trunc` needs `::timestamptz`; `ts_highlight` and `ts_offsets` need an `@@` in the same sub-query; `VARCHAR(n)` is accepted but not enforced |
| Docker | Latest image | `serenedb/serenedb:26.09.1.3` (newest multi-arch tag; 26.10.x is amd64-only), published on `127.0.0.1` only, because auth is trust and Docker bypasses ufw |
| Machine budget | The laptop might struggle | Derive 14 s, `bgl_idx` 5.2 s, full rebuild about 20 s: risk retired |

**Team decisions that replace this doc's**

- Deadline Sunday 18 Oct, 23:59. The demo is a recorded video of at most 5 minutes, with a 3-minute cut. The per-team Q&A slot is Saturday 18:00–20:00. Sleep Sunday 00:00–08:00.
- Role scope is enforced in the database (views, `GRANT`, `SET ROLE`) as core Stage 4 work, so §9b is no longer a bonus.
- Every answer passes a numeric lint (a number absent from the tool output is rejected) as well as `verify_evidence` and the manager lint.
- The worked investigations are chosen and measured. W1 (BGL): a 152,183-line burst on one node in 6h22m (the team plan's 136,209 stops at 23:00; verified 17 Oct) against a 22,529-node fleet event; by episodes, ciod and Lustre lead. W2 (OpenStack): lifecycle duration puts all 4 labelled anomalies at positions 1–4; 188 error lines are 8 tracebacks of one imagecache bug; 6 CRITICAL auth lines. §8's mining step is done; keep its validation and README structure.
- Bonus order: MCP packaging (9f) → eval harness (9d) → huge-data bench (9c) → workspace indexes (9a, only if a re-probe shows an effect) → an `investigations/` write-up.
- Submission adds an MIT licence, a disclosure section (models, tools, what was built in the window), SereneDB starred on GitHub and the docs MCP connected.

**Who owns what.** Arnie: MCP server, `datasets.py`, evidence ledger, tool contracts, role prompts, answer lints, packaging. Adnan: probe, derive and index, views, ownership map, `sql/50_roles.sql`, golden SQL, independent verification of every number, huge-data bench, ground-truth validation. Interface: searches target `*_idx` by name, tools reach columns only through `datasets.py`, and any number shown on stage is reproducible with `make smoke` or `make demo`.

**Tool names.** The team catalogue wins: `count_events` (§5's `count_by`), `top_signatures` (`rank_recurring`; give it `rank_by` = lines, episodes, nodes, blast radius or persistence, which covers `prioritize_risks`), `nearby_events` (`get_context`), `episodes` (`find_episodes`), `durations` (`metric_stats`; add latency percentiles for W2's engineer step), `ownership` (new), plus `describe_data`, `search_logs`, `trend` and `what_changed`. Keep `verify_evidence` as the eleventh core tool.

**Stage map** (`/stage N` uses the team's stage numbers)

| Team stage | When | Owner | Read in this doc |
| --- | --- | --- | --- |
| 0–1 Probe, data layer | Done | Adnan | Stage 0–1 acceptance as a checklist; §3; §12 |
| 2 MCP skeleton | Sat 12:00–14:00 | Arnie | Stage 2; §5 |
| 3 W1/W2 tools and views | Sat 14:00–17:00 | Adnan (SQL, views), Arnie (tools) | Stage 3; Stage 4 steps 1–2; §8; §12 |
| Q&A prep and slot | Sat 17:00–20:00 | Both | Team plan §13 |
| 4 Roles, answer contract, lints | Sat 20:00–24:00 | Arnie; Adnan ports `sql/50_roles.sql` | §6; §9b; Stage 4 steps 3–4 |
| Sleep | Sun 00:00–08:00 | — | Long jobs from Stage 4 step 7 |
| 5 Validation, eval harness | Sun 08:00–12:00 | Adnan (ground truth), Arnie (verify) | §8 validation; §9d; Stage 5 |
| 6 README, clean-check, slides | Sun 12:00–15:00 | Both | Stage 7; §10 |
| 7 Video (5 min and a 3-min cut) | Sun 15:00–19:00 | Both | §10 run of show |
| 8 Submission, repo public | Sun 19:00–22:00 | Both | §10 checklist |

**Settle with Arnie today**

1. The team plan keeps component names out of manager answers, but the brief tells managers to use "measured frequency and affected components". Keep raw log text out of the manager view, but name the affected components and owning teams.
2. `validate` must stay a script the agent cannot call (team plan §9), not the optional tool its §7 lists.

## 1. How to run this plan with Claude Code

Claude Code works from four repo files: the team's `PLAN.md` (schedule, split, measured numbers; see Section 0), `docs/build-plan.md` (this doc, exported as Markdown: contracts, SQL, verification), `CLAUDE.md` (rules, stack, SereneDB facts) and the kit's `/stage N` command. Nothing here is pre-written code, so all code is created inside the hackathon window.

**Before H0 (tonight, about 20 minutes)**

1. Ask the organizers for the exact submission deadline and format. Their Q&A of 17 Oct settled the rest: there is no shared instance and no supplied loader, schema or ownership table. Each team runs SereneDB locally in Docker (no credentials by default) and ships its own schema, loading scripts and ownership table in the repo.
2. The team repo exists (private until Stage 8). Unzip the kit at its root without overwriting anything: this doc lands as `docs/build-plan.md`, and if the repo already has `CLAUDE.md`, `.mcp.json` or `.gitignore`, merge ours into them. Re-export this doc after any edit here.
3. Install: Python 3.11+, `uv`, `psql`, Docker, Node 18+ (for MCP Inspector and the optional `.mcpb` bundle), Claude Desktop (for the demo).
4. Connect the SereneDB docs MCP server to Claude Code with the organizers' guide. The kit's `.mcp.json` already declares it (`https://api.serenedb.com/mcp`): approve it when Claude Code first starts in the repo, then check with `/mcp`. To add it for every project instead: `claude mcp add --scope user --transport http serenedb-docs https://api.serenedb.com/mcp`.
5. Run SereneDB locally with the team's pinned image: `docker run -d --name serenedb -p 127.0.0.1:7890:7890 -v serenedb-data:/var/lib/serenedb -v "$PWD/data":/data serenedb/serenedb:26.09.1.3`, then `psql -h 127.0.0.1 -p 7890 -U postgres`. 26.09.1.3 is the newest multi-arch tag (26.10.x is amd64-only). Publish on loopback only: auth is trust and Docker bypasses ufw; a teammate connects over Tailscale, never the public IP.

**Operating loop for every stage**

1. `/clear`, then `/stage N`. Claude reads `CLAUDE.md`, `PROGRESS.md` and the Stage N section of `PLAN.md`.
2. Claude proposes the stage's task list in plan mode. You approve or trim it.
3. Claude builds, runs the stage's acceptance checks, commits as `stage N: <summary>` and appends to `PROGRESS.md` (done, decisions, measured numbers, open issues).
4. You read the acceptance output. If a check fails: `/stage N fix: <what failed>`.
5. At each MVP gate run `/judge` to score the repo against the rubric.

**Parallel work**

- Use git worktrees for independent tracks: `git worktree add ../exhibit-mcp -b mcp`. Good splits: data and SQL layer, MCP server and prompts, investigation and docs. Merge at every stage boundary.
- Long jobs (index builds, remote Parquet scans, eval batches) run in a second terminal or before a sleep block, never while you wait.
- Use the strongest model for Stages 0–1, tool descriptions and the worked investigation; a faster model for boilerplate and tests.

**If you have teammates**

| Person | Owns | Stages |
| --- | --- | --- |
| A | Data layer: loader, views, indexes, SQL library, episodes | 0, 1, 3, 9a–9c |
| B | MCP server: tools, prompts, resources, evals, packaging | 2, 3, 4, 9d–9f |
| C | Story: worked investigation, validation, README, slides, demo | 5, 7, 8 |

Solo: run two Claude Code sessions (data + MCP) from H2 to H16, then one.

**Kit contents**

| File | Purpose |
| --- | --- |
| `docs/build-plan.md` | This doc, as the design reference; the team's `PLAN.md` runs the schedule and is never overwritten |
| `CLAUDE.md` | Non-negotiable rules, stack, SereneDB facts and gotchas, definition of done |
| `KICKOFF.md` | The H0 checklist, the first prompt, the two-session setup and the overnight prompts |
| `PROGRESS.md` | Running log: H0, stage log, requirements tracker, decisions, measured numbers, background jobs |
| `.claude/commands/stage.md` | `/stage N` runner with `auto` and `fix:` modes and a clock check against H0 |
| `.claude/commands/checkpoint.md` | Commit, update `PROGRESS.md`, print the requirements tracker |
| `.claude/commands/verify.md` | Re-derives every number in an answer or investigation with independent SQL |
| `.claude/commands/judge.md` | Scores the repo against the four judging criteria, the minimal requirements and both awards |
| `.claude/commands/unstuck.md` | A 20-minute way out of a blocker: reproduce, classify, tested alternative, fallback |
| `.claude/agents/*.md` | Subagents: `sql-verifier`, `rubric-judge`, `docs-writer`, `serenedb-expert` |
| `.claude/settings.json` | Build-time permission allowlist, trimmed before the repo goes public |
| `.mcp.json` | SereneDB docs server; Stage 2 adds our own server |
| `.gitignore` | Keeps `.env`, raw data, logs and local state out of git |

## 2. The thesis: what wins

Most of the 200+ teams will ship the same baseline with Claude Code: a loader, four SQL tools, an MCP server and three answers. We win on what a baseline cannot fake: every number is re-runnable, log lines are never confused with incidents, answers are checked against ground truth, and the tools use SereneDB features most teams will not find.

**Product:** *Exhibit* — role-aware log intelligence on SereneDB. Tagline: “Every number is an exhibit: a query you can re-run.” Rename freely.

**The baseline we must beat.** A search tool built on `ILIKE` or one `@@` predicate, a count by component, Claude answering three questions, a README. Judges will see dozens of these.

**Ten differentiators**

| # | Differentiator | What the judges see | Lifts |
| --- | --- | --- | --- |
| 1 | Evidence ledger + `verify_evidence` | Every tool call gets an ID (`E-0042`) holding the exact SQL, parameters, scope, rows in scope, rows returned, truncation flag and a result hash. Answers cite IDs; one call re-runs and confirms them. | Recommendation quality, Best MCP |
| 2 | Lines are not incidents | `find_episodes` coalesces alert lines in time (per location) and space (across locations), following the BG/L log-filtering literature. Episode counts are reported at three gap settings so their sensitivity is visible. | Recommendation quality |
| 3 | Ground-truth validation the agent never sees | BGL alert labels and the four labelled OpenStack failure instances are used only by a validation script, reported separately. | Credibility across all criteria |
| 4 | “What changed” from the term dictionary | Significant terms: foreground window vs baseline, computed with `ts_dict_agg` / `ts_dict_count` on the inverted index. | Engineer insight, SereneDB depth |
| 5 | Exact totals and facets on every search | Each search returns the exact match count plus component, level and team breakdowns over all matches, so a sample is never read as a frequency. | Search and analytics |
| 6 | Agent-managed workspace indexes | Partial inverted indexes over an incident window, created and dropped by the agent, with build time, query savings and break-even measured. Also over the remote 1B-row OTel Parquet. | Optional extension, huge-data award |
| 7 | One tool layer, many datasets | A dataset registry maps logical fields to physical columns; the same tools run on BGL, OpenStack and OTel Parquet. | Huge-data award, Execution |
| 8 | Least-privilege agent roles | SereneDB has no `CREATE POLICY` yet, so per-role row and column scope is enforced with views, `GRANT` and column privileges; the MCP server connects as the role. | Row-level security bonus |
| 9 | Measured agent quality | An eval harness runs 12 role questions headless and scores tool choice and numeric accuracy against golden SQL. | Best MCP (tool selection) |
| 10 | Judge-friendly packaging | `.mcp.json` auto-discovery, one-line `claude mcp add`, Claude Desktop config, optional `.mcpb` bundle, streamable HTTP, and the three roles as MCP prompts (slash commands). | Execution, Best MCP |

**Score map**

| Criterion | Weight | How we earn it | Where it shows |
| --- | --- | --- | --- |
| Role-appropriate insight | 30% | Three playbooks with different evidence: raw lines + context + term shifts; recurring aggregates + trends + owners; a ranked risk register. Different next steps per role, enforced by MCP prompts. | Demo 0:30–3:45, `investigations/01-*` |
| Search and analytics together | 25% | Full-text search with phrase, proximity, fuzzy, BM25 and highlighting under time filters; whole-corpus counts per dataset and team; trends with change statistics; exact totals, facets, truncation flags. | Evidence pages, demo |
| Recommendation quality | 25% | Answer contract (Observed with IDs / Hypothesis / Not established / Next step), `verify_evidence`, lift over chance for co-occurrence, episode sensitivity. | Every answer |
| Execution | 20% | Clean-checkout `Makefile`, README quickstart, tool docs generated from the live server, rehearsed 5-minute demo with a backup video, the novelty items above. | Repo, demo |
| Best MCP Server (separate) | — | Tool descriptions written to Anthropic's tool-design guidance, annotations, structured output, limits, helpful errors, prompts, resources, eval report, four install paths. | README, `evals/` |
| Huge datasets (separate) | — | A scale ladder from 4.7M to 1B+ rows with measured time, rows and index size; zero-ETL index over remote Parquet; agent workspace on the lake. | `bench/`, demo 3:45 |

## 3. What the research established

The design rests on four findings: SereneDB answers search, counts and facets from one inverted index, but only when queried by index name; it has no row-security policies; the OpenStack failures are timing anomalies, not keyword anomalies; and SereneDB's own benchmark already uses the hackathon's OTel corpus, so the judges know it intimately. The organizers' Q&A (17 Oct) adds a fifth: there is no shared instance and no supplied loader, schema or ownership table, so each team runs SereneDB locally in Docker and ships its own in the repo.

**SereneDB**

| Fact | What we do with it | Source |
| --- | --- | --- |
| PostgreSQL wire protocol on port 7890; `psycopg` 3.2 and `psycopg2` 2.9 have full support | Python client = `psycopg` 3 | [Quick Start](https://serenedb.com/docs/quick-start), [Clients](https://serenedb.com/docs/clients) |
| Full-text search runs on an IResearch inverted index; queries select **from the index by name**; `@@` against the base table raises an error | Every search tool targets `*_idx` relations | [Inverted Index](https://serenedb.com/docs/sql/indexes/inverted) |
| Query constructors: `ts_phrase`, `##` proximity, `ts_starts_with`, `ts_like`, `ts_regexp`, `ts_levenshtein`, `ts_any`/`ts_all`/`ts_compound`, `to_tsquery` (Lucene syntax), `websearch_to_tsquery`; combine with `&&` (and), a double pipe (or) and `!!` (not) | Search modes: words, all words, phrase, near, fuzzy, prefix, Lucene | [Full-Text Search](https://serenedb.com/docs/sql/indexes/inverted/full-text-search) |
| `BM25` plus six other scorers; WAND top-k pruning when the index is built `WITH (optimize_top_k = 'bm25(1.2, 0.75)')` | Relevance mode with `LIMIT k` stays fast | [Ranking](https://serenedb.com/docs/sql/indexes/inverted/ranking) |
| Columns listed without a dictionary are exact keyword fields; numeric and timestamp columns support range matching inside the index | IDs, levels, components and time filters live in the same index as the text | [Inverted Index](https://serenedb.com/docs/sql/indexes/inverted) |
| `ts_dict_agg` / `ts_dict_count` / `ts_dict_freq` read the term dictionary; with document filters (`@@` matchers, conditions on other indexed columns) they return facet counts over the matching documents. A plain `GROUP BY` is rewritten onto the dictionary only for one keyword key whose `WHERE` touches that column alone (`EXPLAIN` shows `TsDict:`); otherwise it falls back to a document scan with the same result. `GROUPING SETS` and filtered facets need `NOT NULL` columns | Facets on every search and significant terms; derived tables declare keyword columns `NOT NULL` and store `'UNKNOWN'`, never `NULL`; claim dictionary-served counts only when `EXPLAIN` shows `TsDict:` | [Term Dictionary](https://serenedb.com/docs/sql/functions/search/term-dictionary), [Significant Terms](https://serenedb.com/docs/cookbook/search/significant-terms) |
| `COUNT(*)` with `@@` filters is answered from the index alone | Exact totals on every search are cheap | [Indexing Views](https://serenedb.com/docs/sql/indexes/inverted/views) |
| Partial inverted indexes are documented (`CREATE INDEX … USING inverted (…) WHERE <predicate>`), but on 26.09.1.3 the team measured no effect. `sdb_indexes()` and `sdb_metrics` report no index size. `EXPLAIN` shows `IRESEARCH_SCAN` | Workspace indexes are probe-gated (§9a); sizes come from the data directory; plan snippets go into evidence | [Inverted Index](https://serenedb.com/docs/sql/indexes/inverted), [Maintenance](https://serenedb.com/docs/sql/indexes/inverted/maintenance) |
| Indexes are eventually consistent: run `VACUUM (REFRESH_TABLE) t` after a load; loading first and indexing after gives a more compact index | Bootstrap order: load → derive → index → refresh | [Maintenance](https://serenedb.com/docs/sql/indexes/inverted/maintenance) |
| `read_parquet` over `https://` and `s3://` with globs; an inverted index on a view over the reader keeps rows in the files (zero-ETL); `REINDEX INDEX` refreshes; a list of files makes the view “generic” | OTel track: view + index over remote Parquet, one glob per view | [External Data](https://serenedb.com/docs/sql/indexes/inverted/external-data), [Indexing Views](https://serenedb.com/docs/sql/indexes/inverted/views) |
| Window functions, `WITH RECURSIVE`, `LATERAL`, `GROUPING SETS`, `ASOF JOIN`, `percentile_cont`, `regr_slope`, `date_trunc`, `date_bin`, `generate_series`, `GROUP BY ALL` | Episodes, trends, precursors and latency stats all computed in SQL | [PostgreSQL Compatibility](https://serenedb.com/docs/compatibility/core-sql-compatibility), [AsOf Join](https://serenedb.com/docs/cookbook/sql_features/asof_join) |
| Row security policies: not supported (issue #212). `GRANT`, column privileges and `SET ROLE` are enforced; views read their sources with the owner's privileges | Per-role scope through views + `GRANT`; say so honestly | [PostgreSQL Compatibility](https://serenedb.com/docs/compatibility/core-sql-compatibility), [Privileges](https://serenedb.com/docs/security/privileges) |
| Gotchas: no `VARCHAR(n)`; `to_timestamp` only takes epoch numbers (use `strptime` for text); `regexp_extract` returns `''` on no match; no `to_char` / `to_date`; integer division truncates as in PostgreSQL; unquoted identifiers fold to lowercase, so mixed-case Parquet columns need quotes (`"Body"`); `UUID`, `DECIMAL`, `HUGEINT` and `INTERVAL` columns cannot be indexed; `INCLUDE` columns are stored but cannot be searched | Encoded in `CLAUDE.md` so Claude Code avoids them | [PostgreSQL Compatibility](https://serenedb.com/docs/compatibility/core-sql-compatibility), [Inverted Index](https://serenedb.com/docs/sql/indexes/inverted) |
| SereneDB's SearchBench runs 92 search and analytics queries over the same OTel log corpus at 100M, 1B and 10B rows on a 32-vCPU, 128 GB machine | Our huge-data numbers will be read against theirs: report hardware, never claim speed records | [SearchBench repo](https://github.com/serenedb/searchbench), [Benchmarks](https://serenedb.com/docs/benchmarks) |

**Datasets**

| Fact | What we do with it | Source |
| --- | --- | --- |
| BGL: 4,747,963 lines over 214.7 days; a `-` in the first column marks a non-alert line, anything else is an alert category | `is_alert` and `alert_category` drive recurrence and episodes | \[Brief\], [Loghub paper](https://arxiv.org/pdf/2008.06448) |
| Loghub-2.0 annotates 4,631,261 BGL lines with 320 templates and 207,632 OpenStack lines with 48 templates | The brief's “320 templates” is our target granularity; with no supplied schema (Q&A), Stage 1 derives a masked-message template key | [Loghub-2.0](https://github.com/logpai/loghub-2.0) |
| OpenStack: 207,820 lines, 2,070 VM cases, four labelled injected failures; the failures reuse normal templates and show a large create-image-to-VM-started delay plus extra `/servers/detail` polling | OpenStack analysis is about timing and counts, not keywords; labels used only for validation | [Xin 2025](https://journal.umy.ac.id/index.php/eist/article/view/31232) |
| OTel corpus: Parquet files of 1B rows each, sorted by timestamp, bucket in eu-west-3; columns `Timestamp`, `TraceId`, `SpanId`, `SeverityText`, `SeverityNumber`, `ServiceName`, `Body` plus attribute maps; about 40 GB per file | Time-sliced views prune row groups; `TraceId` groups the log lines of one request (logs only; spans and metrics need Nezha or RCAEval) | [ClickHouse benchmark](https://clickhouse.com/blog/elasticsearch-log-analytics-clickhouse), [TextBench schema](https://github.com/ClickHouse/TextBench/blob/main/clickhouse/create.sql), [SearchBench repo](https://github.com/serenedb/searchbench) |
| Research licence; cite Zhu et al. (ISSRE 2023), and Oliner & Stearley (DSN 2007) for BGL | Citations in README and slides | \[Brief\], [Loghub-2.0](https://github.com/logpai/loghub-2.0) |

**MCP and Claude**

| Fact | What we do with it | Source |
| --- | --- | --- |
| MCP Python SDK v2 is the stable line for the 2026-07-28 spec; `pip install mcp` now installs 2.x; the server class is `MCPServer` (`from mcp.server import MCPServer`); v1 lives on a branch | Pin `mcp[cli]>=2,<3` (the `cli` extra provides `mcp dev` and `mcp run`); fallback `mcp[cli]>=1.28,<2` with FastMCP if v2 blocks for more than 30 minutes | [python-sdk](https://github.com/modelcontextprotocol/python-sdk) |
| Typed returns become `outputSchema` + `structuredContent`; the client exposes `result.structured_content`; `mcp dev` opens the Inspector; `mcp run … --transport streamable-http` serves HTTP | Pydantic return models on every tool; smoke tests through the SDK client | [python-sdk](https://github.com/modelcontextprotocol/python-sdk) |
| The SereneDB docs site publishes its docs MCP server at `https://api.serenedb.com/mcp` | Connected to Claude Code at H0 | [Serene Docs Search](https://serenedb.com/docs/clients/serene-docs-search) |

## 4. Architecture and data model

One Python package sits between Claude and SereneDB: an MCP server whose tools compile role questions into parameterised SQL, run it in SereneDB, and return small structured results plus an evidence record. All search and arithmetic happen in the database; Python only shapes results and runs statistics on already-aggregated rows.

```text
Claude Desktop · Claude Code · claude.ai connector · headless eval runner
                     │  MCP (stdio or streamable HTTP)
                     ▼
        exhibit MCP server (src/exhibit/mcp_server.py)
        tools · resources · prompts · server instructions
                     │  dataset registry → parameterised SQL library
                     ▼
SereneDB :7890 ─ bgl_idx / os_idx (inverted) · bgl_ev / os_ev · episodes
                     │
                     └─► exhibit_evidence ledger ◄── verify_evidence re-runs the stored SQL
```

Claude reaches the server over MCP; each tool call runs parameterised SQL in SereneDB and writes an evidence row, the highlighted path.

**Layers**

| Layer | Lives in | Contents |
| --- | --- | --- |
| Raw | SereneDB, loaded by our own loader (make load) from the Zenodo files | BGL table, OpenStack table, team-ownership table |
| Derived | `sql/20_derive.sql` | `bgl_ev`, `os_ev`: typed timestamps, topology, parsed request fields, team, `NOT NULL` keyword columns |
| Search | `sql/30_indexes.sql` | `bgl_idx`, `os_idx` inverted indexes; later `otel_idx` over remote Parquet; `ws_*` workspace indexes |
| Analytics | `sql/40_episodes.sql` | `episodes` table at three gap settings; precursor and rollup views |
| Access | `sql/50_roles.sql` | Role views and `exhibit_engineer`, `exhibit_lead`, `exhibit_manager` database roles |
| Evidence | `exhibit_evidence` table (local SQLite fallback) | One row per tool call |
| Tools | `src/exhibit/` | Dataset registry, SQL library, tools, statistics, ledger |
| Interface | `src/exhibit/mcp_server.py` | MCP tools, resources, prompts over stdio and streamable HTTP |
| Clients | — | Claude Desktop, Claude Code, claude.ai remote connector, headless eval runner |

**`bgl_ev` (one row per BGL line)**

| Column | Type | Derivation |
| --- | --- | --- |
| `id` | BIGINT, primary key | Line number from the loader |
| `ts` | TIMESTAMP | Epoch column via `to_timestamp`, or `strptime(time, '%Y-%m-%d-%H.%M.%S.%f')` for microseconds |
| `alert_category` | VARCHAR | First column; `'NONE'` when it is `-` |
| `is_alert` | BOOLEAN | `alert_category <> 'NONE'` |
| `node`, `node_kind` | VARCHAR | Raw location; kind from the letter after the node card (C compute, I I/O, L link card), else `'OTHER'` |
| `rack`, `midplane`, `nodecard` | VARCHAR | Prefixes of the location string (`R02`, `R02-M1`, `R02-M1-N0`); `'UNKNOWN'` when absent |
| `component`, `level` | VARCHAR | Raw fields |
| `level_rank` | SMALLINT | INFO 1, WARNING 2, SEVERE 3, ERROR 4, FATAL and FAILURE 5 (confirm the level set in Stage 1) |
| `template_id` | VARCHAR | Masked message (digits, hex values and IDs replaced by <\*> with regexp\_replace), else `'UNKNOWN'` |
| `team` | VARCHAR | Ownership join; `'UNOWNED'` when unmapped |
| `content` | VARCHAR | Message text |

**`os_ev` (one row per OpenStack line)**

| Column | Derivation |
| --- | --- |
| `id`, `ts`, `source_file` | Line number; date + time via `strptime`; `normal1`, `normal2` or `abnormal` |
| `service`, `logger`, `level`, `pid` | `nova-api` / `nova-compute` / `nova-scheduler` from the file prefix; Python logger such as `nova.compute.manager` |
| `req_id`, `tenant_id`, `instance_id` | `regexp_extract` on `req-…` and `[instance: …]`, wrapped in `NULLIF(…, '')`, then `'NONE'` for keyword columns |
| `http_method`, `endpoint`, `status`, `resp_len`, `latency_s` | From `"GET /v2/… HTTP/1.1" status: 200 len: 1893 time: 0.2477829`; IDs in paths replaced by `{id}` |
| `spawn_s`, `build_s` | From `Took N seconds to spawn` / `to build instance` |
| `team`, `content` | Ownership join; message text |

**`exhibit_evidence` (one row per tool call)**

`evidence_id` (`E-<session>-<n>`, such as `E-K7Q2-0001`, so parallel sessions and the SQLite fallback never collide; examples shorten it to `E-0001`), `created_at`, `session_id`, `role`, `tool`, `params` (JSON), `sql` (exact text), `scope` (dataset, time range, filters), `rows_in_scope`, `row_count`, `returned`, `truncated`, `elapsed_ms`, `result_json` (the full returned payload, already capped at 200 rows and 400 buckets, so every answer can be checked against it), `result_sha256` (over the stable part of the result: row ids, keys, counts and rounded metrics, not raw BM25 scores, which can shift after index compaction), `plan_excerpt` (the `IRESEARCH_SCAN` lines from `EXPLAIN`). If the instance refuses writes, the same record goes to `.exhibit/evidence.sqlite` and the tool says so.

**Dataset registry.** `datasets.py` maps logical fields to physical columns for each dataset: index relation, timestamp, text, id, severity rank, location hierarchy, allowed filter and group-by keys, ownership key. Tools only accept registry keys, which blocks SQL injection through identifiers and lets the same tools run on OTel Parquet later.

**Index sketch (Stage 1 confirms the tokenizer with `ts_lexize`)**

```sql
CREATE TEXT SEARCH DICTIONARY log_text (
  template = 'text', locale = 'en_US.UTF-8', case = 'lower',
  stemming = false, accent = false, frequency = true, position = true);

CREATE INDEX bgl_idx ON bgl_ev
  USING inverted (id, content log_text, ts, level_rank, alert_category,
                  component, level, node, node_kind, rack, midplane,
                  nodecard, team, template_id)
  WITH (optimize_top_k = 'bm25(1.2, 0.75)');

VACUUM (REFRESH_TABLE) bgl_ev;
```

The team's `sql/20_indexes.sql` holds the DDL that actually ran on 26.09.1.3; prefer it over this sketch. Indexing `id` as a numeric field lets `nearby_events` (`get_context`) fetch neighbouring lines with `id @@ ts_between(a, b, true, true)` instead of a table scan.

## 5. MCP tool catalogue

Eleven read-only tools cover the three roles, plus four optional tools for workspace indexes and traces (and `open_evidence_board` if track 9e is built). Keep the count there: each extra tool costs the agent selection accuracy, so new capability goes into parameters, not new tools.

**Core tools (read-only)**

| Tool | Use when | Key inputs | Returns | SereneDB features |
| --- | --- | --- | --- | --- |
| `describe_data` | First call in a session; unsure what fields or values exist | `dataset?` | Row counts, time span, fields with meaning, top values per facet, ownership coverage, query tips | `ts_dict_agg` facets, `COUNT(*)` from index |
| `search_logs` | Engineer: find the error lines for a symptom | `dataset`, `query`, `match` (`any` \| `all` \| `phrase` \| `near` \| `fuzzy` \| `prefix` \| `lucene`), `time_from`, `time_to`, `filters`, `sort` (`relevance` \| `time_asc` \| `time_desc`), `limit` ≤ 200 (default 20), `offset` | Exact `total_matches`, rows with highlights, facets over **all** matches, `truncated`, `next_offset` | `@@` constructors, `BM25` + WAND, `ts_offsets` + `ts_highlight`, `ts_dict_agg` |
| `get_context` | Engineer: what happened just before and after an event | `dataset`, `anchor` (`event_id` or `ts` + location), `scope` (`node` \| `nodecard` \| `midplane` \| `rack` \| `global` \| `instance` \| `request`), `before`, `after`, `max_events` | Timeline with Δt from the anchor; identical lines collapsed into runs (“× 812 on 3 nodes”); level counts before vs after | Range on indexed `id` / `ts`, keyword filters |
| `count_by` | Team lead / manager: how often, where, which team | `dataset` or `all`, `group_by` (1–2 registry keys), `time_from`, `time_to`, `filters`, optional `text_query`, `top` | Groups with lines, share, distinct locations, first and last seen; totals; scope statement; a reminder that lines are not incidents | Facet counts with `ts_dict_agg` / `ts_dict_count` for one key (dictionary-served when `EXPLAIN` shows `TsDict:`); `GROUP BY` for two keys and `GROUPING SETS` over `NOT NULL` columns otherwise |
| `trend` | Team lead: rising or falling? | `dataset`, filter (`text_query` / `alert_category` / `component` / `team`), `bucket` (`auto` \| `hour` \| `day` \| `week`), `split_by?` (≤ 5 series) | Buckets, total, slope per bucket, recent-vs-baseline rate ratio with z, spikes by robust z-score, a trend label | `date_trunc`, `regr_slope`, `percentile_cont` |
| `find_episodes` | Any role: turn matching lines into incidents | `dataset`, signature filter, `gap` (default 5 min), `spatial` (`node` … `system` \| `instance`), time range | Episodes with start, end, duration, lines, locations; summary lines vs episodes vs locations; sensitivity at 1, 5 and 60 minutes | `LAG` + running `SUM` windows |
| `rank_recurring` | Team lead: which problems recur most | `dataset` or `all`, time range, `by` (`alert_category` \| `template` \| `component`), `min_episodes`, `top` | Ranked signatures with team, lines, episodes, locations, active days, trend label, an example message | Joins with ownership, window functions |
| `what_changed` | Engineer and team lead: what is unusual in a window | `dataset`, `focus` window or `around_event`, `baseline` window (default: preceding window of equal length), filters, `top`, `min_fg` | Significant terms (foreground docs, background docs, lift), signature shifts (observed vs expected), evidence | Significant terms on `ts_dict_agg` / `ts_dict_count` |
| `metric_stats` | OpenStack: latency, spawn time, create-to-start delay | `dataset`, `metric` (`api_latency_s` \| `spawn_s` \| `build_s` \| `create_to_start_s` \| `detail_polls`), `group_by?`, `percentiles`, `outliers` (`iqr` \| `robust_z`) | Distribution per group (n, p50, p90, p95, p99, max), top outliers with IDs | `percentile_cont`, conditional aggregates |
| `prioritize_risks` | Manager: what deserves attention first | `datasets`, time range, `weights?`, `top` | Ranked risks with every measured factor, the score and its breakdown, the formula, the caveat that the score is not an impact estimate | One SQL statement with CTEs |
| `verify_evidence` | Before any final answer; whenever a number is challenged | `evidence_ids` | Per ID: `match` \| `drift` \| `error`, both hashes, row count, time | Re-executes the stored SQL |

**Optional tools (enabled by `EXHIBIT_ENABLE_WORKSPACE=1` / `EXHIBIT_ENABLE_OTEL=1`)**

| Tool | Use when | Returns |
| --- | --- | --- |
| `workspace_create_index` | An investigation will ask many questions about one time window | Index name (`ws_<id>`), rows indexed, build time, size from `sdb_metrics`, expiry |
| `workspace_benchmark` | Proving the trade-off | p50 time per query with the workspace index, with the full index, and with a table scan; break-even query count |
| `workspace_drop_index` | Investigation finished (also auto-dropped after a TTL) | Confirmation; refuses any index it did not create |
| `trace_timeline` | OTel: follow one request across services | Every log line for a `TraceId` in time order, grouped by service, with gaps |

**Contract every tool follows**

- **Evidence block** in every response: `evidence_id`, exact SQL, parameters, scope (dataset, time range, filters), rows in scope, rows returned, `truncated`, elapsed ms.
- **Scope sentence** first, e.g. “BGL, full corpus (2005-06-03 → 2006-01-04, 4,747,963 lines); filter: alert\_category = KERNDTLB.”
- **Limits:** 20 rows by default, 200 maximum; messages cut at 300 characters (2,000 with `detail='full'`); at most 400 buckets; 10 values per facet; responses under about 8k tokens.
- **Truncation message that teaches:** “Showing 20 of 18,342 matches (exact count). Narrow with `time_from`/`time_to` or `filters`, or page with `offset=20`.”
- **Errors that teach:** invalid values list the valid ones; bad timestamps show the expected ISO format; a timeout says which filter to add.
- **Hints:** `next_suggested_tools`, e.g. after `search_logs` → `get_context` on the earliest match, `find_episodes` for frequency.
- **Annotations:** `readOnlyHint: true`, `idempotentHint: true`, `openWorldHint: false` on read tools; `workspace_drop_index` is the only `destructiveHint: true`.
- **Structured output:** Pydantic return models (`outputSchema` + `structuredContent`) plus a short text rendering for clients that ignore structure.
- **Untrusted text:** log messages come back in a `message` field and are never treated as instructions.

**Loading in Claude Code.** Claude Code defers MCP tools until its tool search finds them; only tool names and server instructions load at the start. Keep the server instructions under 4,096 characters and open them with when to use Exhibit, start each description with the words a user would search for, and set `_meta["anthropic/alwaysLoad"] = true` on the eleven core tools so they load up front ([Claude Code MCP docs](https://code.claude.com/docs/en/mcp)).

**Resources:** `exhibit://datasets`, `exhibit://schema/{dataset}`, `exhibit://ownership`, `exhibit://glossary/{dataset}` (top messages per alert category, derived from data, not from memory), `exhibit://evidence/{evidence_id}`, `exhibit://playbook/{role}`.

**Prompts (slash commands in Claude):** `engineer_investigate(symptom, around?)`, `team_lead_review(period?, team?)`, `manager_brief(period?)`, `worked_investigation(topic)`.

**Server instructions** (the MCP `instructions` field) restate the rules: cite an evidence ID for every number, say “log lines” unless the number came from `find_episodes`, keep observed facts apart from hypotheses, never estimate cost, downtime or customer impact, and call `verify_evidence` before the final answer.

## 6. Role playbooks and the answer contract

The three roles share one agent and one corpus but differ in the question, the evidence selected, the level of detail and the next step. Answer length is never the difference, because the brief rules that out explicitly.

|  | Engineer | Team lead | Manager |
| --- | --- | --- | --- |
| Question shape | What failed on X around T, and what happened just before and after? | What keeps recurring over a stated period, how often, and who owns it? | Which observed problems deserve attention first, and what should happen next? |
| Tool sequence | `search_logs` (phrase or near, time filter) → `get_context` on the earliest match → `what_changed` (pre-failure window vs baseline) → `find_episodes` (that signature, node or midplane scope) → `verify_evidence` | `rank_recurring` → `trend` on the top three (weekly) → `count_by` (team × signature) → `find_episodes` sensitivity → `verify_evidence` | `prioritize_risks` (both datasets) → `count_by` (dataset and team totals, whole corpus) → `trend` on the top risk → `verify_evidence` |
| Evidence shown | Raw lines with highlights, a ±5-minute timeline, term shifts | Ranked aggregates, weekly trend with change statistics, owner team | Ranked risk register with measured factors; no raw text unless asked |
| Detail | Node IDs and timestamps to the second | Per-signature metrics over the period | Three to five risks, one line each |
| Next step | One specific diagnostic check and the query to run next | Investigation order with rationale and owner; an alert threshold worth adding | A decision: who acts on what this sprint, how success is measured, what stays unknown |
| Never | Claim a root cause from co-occurrence | Call log lines incidents | Mention money, downtime or customer impact |

**Answer contract (all roles; enforced by the MCP prompts and the server instructions)**

```text
Scope: <datasets, resolved time range, filters>
Answer: <2–4 sentences written for this role>

Observed (measured)
- <fact with its number> [E-0012]

Likely explanation (hypothesis, not established)
- <hypothesis> — supported by [E-0014]; would be contradicted if <check>

Not established by these logs
- <cause, impact or anything not measured>

Recommended next steps
1. <action> — why: [E-0013]; owner: <team>

Evidence
| ID | Tool | What it shows | Rows in scope | Truncated |
```

**Rules behind the contract**

- Every number under *Observed* cites an evidence ID, and `verify_evidence` runs on all cited IDs before the answer is sent.
- Frequencies read “N log lines (M episodes at a 5-minute gap)” whenever episodes were computed.
- Co-occurrence is reported with its lift over chance and always sits under *hypothesis*.
- Relative periods (“last 8 weeks”) anchor to the dataset's last timestamp, not today: BGL ends in January 2006 and OpenStack in May 2017. The scope line prints the resolved dates.
- The manager answer passes a lint in the eval harness: no currency symbols, “downtime”, “customers”, “revenue” or “SLA” unless quoted from the logs.

**Question bank (for the prompts, the demo and the evals)**

| Role | Example questions |
| --- | --- |
| Engineer | “Investigate the first FATAL burst in `<category>` on `<midplane>` in `<month>` — what preceded it?” · “Instance `<uuid>` was slow to start. What happened, step by step?” · “Find the `ciod` read failures in the week of `<date>` and show the minutes before the first one.” |
| Team lead | “What recurred most in the last 8 weeks of BGL, by owning team?” · “Is `<category>` getting worse week over week?” · “Which OpenStack endpoints have the worst p95 latency, and is one service responsible?” |
| Manager | “What are the top three risks across both systems, and what should we fund first?” · “Which team carries the most recurring problems, and is that growing?” · “What do the logs not tell us about impact?” |

Fill the angle-bracket values in Stage 5 from real data, so every demo question has a non-empty, interesting answer.

## 7. Stage-by-stage execution plan (H0–H48)

Nine stages with one hard gate: every minimal requirement works end to end by H16 (tag `v0.1`), before any bonus work. H0 is the official start; if the real window is shorter than 48 hours, scale every stage proportionally but keep the MVP gate at one third of the window and the submission freeze two hours before the deadline. Solo builders sleep from H22 to H27 with long jobs running.

| Stage | Hours | Gate |
| --- | --- | --- |
| 0 Recon and rails | H0–H2 | Capability matrix; data loading |
| 1 Data layer | H2–H6 | Derived tables, indexes, golden baseline |
| 2 Walking skeleton | H6–H9 | One cited answer per role through our server |
| 3 Core tools | H9–H16 | **MVP gate: every minimal requirement, tag `v0.1`** |
| 4 Insight tools | H16–H22 | Long jobs started before sleep |
| Sleep | H22–H27 | Long jobs run |
| 5 Worked investigation | H27–H32 | Every number verified |
| 6 Bonus tracks | H32–H38 | Time-boxed tracks |
| 7 Hardening and docs | H38–H44 | Clean clone passes, tag `v1.0-rc` |
| 8 Demo and submission | H44–H48 | **Submit by H46**, tag `v1.0` |

Stages 0–3 deliver the minimal requirements by H16; long jobs run through the sleep block; H46 freezes the submission.

### Stage 0 — Recon and rails (H0–H2)

**Goal.** Everything connected, the data loading, and every SereneDB capability we rely on proven on the real instance.

**Claude Code does**

1. Scaffold with `uv`: `src/exhibit/`, `tests/`, `sql/`, `scripts/`, `seed/`, `docs/`, `investigations/`, `bench/`, `evals/`. Dependencies: `psycopg[binary]>=3.2`, `mcp[cli]>=2,<3`, `pydantic>=2`, `typer`, `rich`, `python-dotenv`, `pytest`, `ruff`. A `Makefile` with `setup`, `db`, `load`, `probe`, `bootstrap`, `test`, `mcp`, `inspect`, `smoke`, `eval`, `demo`, `bench`, `export`, `clean-check`. A complete `.env.example` (`SERENEDB_HOST=localhost`, `SERENEDB_PORT=7890`, `SERENEDB_USER`, `SERENEDB_PASSWORD` (empty by default), `SERENEDB_DB`, `EXHIBIT_SCHEMA`). `scripts/psql.sh` reads `.env`, exports `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE`, and runs `psql`.
2. `src/exhibit/db.py`: psycopg 3 connection factory, `run(sql, params, timeout_s=30)` returning rows, columns and elapsed ms, `explain(sql, params)`, and a guard that refuses anything but `SELECT` / `WITH` / `EXPLAIN` on tool paths.
3. Build our own loader, since nothing is supplied (Q&A, 17 Oct). `make db` runs the Section 1 `docker run` with a pinned image tag. `make load` downloads `BGL.zip` and `OpenStack.tar.gz` from Zenodo into `data/` (`curl -L`, keep `?download=1`), unpacks them, has a streaming script write each log as two columns (line number, raw line) so line order survives, and loads them into `bgl_raw` and `os_raw` with `read_csv('/data/…')` (fallback: `COPY … FROM STDIN` through psycopg). All field parsing stays in SQL (Stage 1). It is idempotent: it skips when the row counts already match. Run it in a second terminal; log to `logs/load.log`; record row counts.
4. `scripts/probe.py` + `sql/00_probe.sql`: in a scratch schema, test each capability below and write `docs/capabilities.md` as a PASS/FAIL table with the exact statement and error text.
   - Privileges: create schema, table, index, role.
   - Search: dictionary, inverted index, `VACUUM (REFRESH_TABLE)`, `@@` with `ts_phrase`, `##`, `ts_levenshtein`, `ts_starts_with`, `to_tsquery`, `websearch_to_tsquery`; `BM25` ordering with `optimize_top_k`, with and without the `norm` flag; `ts_offsets` + `ts_highlight`; `ts_dict_agg` / `ts_dict_count` under a document filter; a one-key `GROUP BY` on the index (`EXPLAIN` shows `TsDict:`); `COUNT(*)` on the index; timestamp range inside the index via `ts_between` and plain `BETWEEN`. Then run the same constructors through psycopg with bound parameters (`ts_phrase(%s)`, `ts_any(%s)` with a Python list, `ts_between(%s, %s, true, false)`), as the tools will; if server-side binding fails, switch to `psycopg.ClientCursor`.
   - Analytics: `LAG` and running `SUM` windows, `ASOF JOIN`, `date_trunc`, `date_bin`, `percentile_cont`, `regr_slope`, `GROUPING SETS`, `regexp_extract`, `strptime`, `to_timestamp`.
   - Operations: partial inverted index + `DROP INDEX`, `sdb_indexes()`, `sdb_metrics`, `EXPLAIN` and `EXPLAIN ANALYZE`.
   - External: `SELECT count(*) FROM read_parquet('https://public-pme.s3.eu-west-3.amazonaws.com/text_bench/part_000.parquet')` (metadata only, no full scan).
   - Security: `CREATE ROLE`, `GRANT`, column `GRANT`, `GRANT USAGE ON SCHEMA`, role membership and `SET ROLE`.
5. Schema recon: tables, columns, row counts, 20 sample rows each, the distinct BGL components and OpenStack services and loggers. From that list write our ownership table, seed/ownership.csv (each one mapped to a team of one fictional platform org), and load it as ownership. Write `docs/DATA_NOTES.md` with each fact next to the SQL that produced it.
6. First `PROGRESS.md` entry, commit, push.

**You do:** start SereneDB in Docker (Section 1 step 5), confirm the deadline with the organizers; paste the `KICKOFF.md` prompt; check `/mcp` shows `serenedb-docs`.

**Acceptance**

- [ ] `make probe` prints the capability matrix, and every FAIL has a fallback noted.
- [ ] Row counts recorded; any difference from 4,747,963 (BGL) and 207,820 (OpenStack) explained.
- [ ] Our ownership table committed as seed/ownership.csv and loaded: every BGL component and OpenStack service/logger mapped to a team of one fictional platform org, labelled as our own in the README.
- [ ] Public repo with a README stub.

**Gate.** If Docker is unavailable, install SereneDB natively (serenedb.com/docs/installation). If a 4.7M-line index strains the laptop, raise Docker's memory limit first, then index fewer columns; log the decision in `docs/decisions.md`.

### Stage 1 — Data layer (H2–H6)

**Goal.** Derived tables and inverted indexes that turn every later question into one statement.

**Claude Code does**

1. Profile with SQL files in `sql/profile/`, appending results to `DATA_NOTES.md`: BGL by alert category, component, level, node kind; time span and lines per day; top 20 messages per alert category; OpenStack by file, service, logger, level; instance and request counts; how many lines carry status, latency or spawn time; lines whose component has no owning team.
2. Tokenizer trial: two or three candidate dictionaries (`split_text(case := 'lower')`, a non-alphanumeric splitter, one with `filter_tokens(max_length := 40)`). Run `ts_lexize` on 25 representative lines: node IDs, hex addresses, `ciod:` prefixes, `[instance: <uuid>]`, `req-…`, URL paths, `status: 200`. Pick one and log why.
3. `sql/20_derive.sql`: create `bgl_ev` and `os_ev` with explicit types, `NOT NULL` keyword columns (sentinels, never `NULL`) and a primary key on `id`, then fill them with `INSERT … SELECT` (columns in Section 4). `CREATE TABLE AS` would leave every column nullable, which sends filtered facets back to a document scan. Keep UUIDs as `VARCHAR` and numbers as `DOUBLE` or `BIGINT`: `UUID`, `DECIMAL`, `HUGEINT` and `INTERVAL` columns cannot be indexed.
4. `owner_map(dataset, component_key, team)` view and a coverage report.
5. `sql/30_indexes.sql`: dictionary, `bgl_idx`, `os_idx` with `optimize_top_k`, then `VACUUM (REFRESH_TABLE)`. Record build time and `sdb_metrics` size.
6. `tests/golden/baseline.json`: whole-corpus counts per dataset, team, alert category and level, computed with plain SQL on the derived tables (not through the index). These are the truth values for every later test.
7. Cross-check five terms: `COUNT(*) FROM bgl_idx WHERE content @@ '<term>'` vs `COUNT(*) FROM bgl_ev WHERE lower(content) LIKE '%<term>%'`. Explain every difference (tokenization) in `DATA_NOTES.md`.

**Acceptance**

- [ ] A phrase search with a 7-day time filter on BGL returns in under a second (time recorded).
- [ ] Whole-corpus counts by team for both datasets match the golden baseline.
- [ ] Each derived column has its non-null rate recorded; parse failures are counted, not ignored.
- [ ] Decisions logged: tokenizer, timestamp source, level ranks, sentinels.

**If it slips:** skip template IDs and keep topology at rack and midplane.

### Stage 2 — Walking skeleton (H6–H9)

**Goal.** Claude answers one question per role through our own MCP server, with evidence IDs, before the full tool suite exists.

**Claude Code does**

1. `datasets.py` registry for `bgl` and `openstack`.
2. `ledger.py`: evidence rows into `exhibit_evidence` (SQLite fallback); `result_sha256` over canonical JSON of the full result.
3. `search_logs` and `count_by` with Pydantic input and output models and the full contract from Section 5.
4. `mcp_server.py`: `MCPServer("exhibit", instructions=...)` with both tools over stdio; entry point `uv run exhibit-mcp`.
5. Add the server to `.mcp.json`, restart Claude Code, confirm with `/mcp`; test in the Inspector with `uv run mcp dev src/exhibit/mcp_server.py`.
6. Ask one rough question per role; save transcripts to `investigations/00-skeleton/`.

**Acceptance**

- [ ] The Inspector lists both tools with schemas, and calls succeed.
- [ ] Each Claude answer cites evidence IDs that exist in the ledger.
- [ ] `pytest tests/unit` is green.

**If SDK v2 costs more than 30 minutes:** pin `mcp[cli]>=1.28,<2`, use `from mcp.server.fastmcp import FastMCP`, log it.

### Stage 3 — Core tool suite and MVP gate (H9–H16)

**Goal.** Every minimal requirement works end to end; tag `v0.1`.

**Claude Code does**

1. `describe_data`, `get_context` (with run collapsing), `trend` (SQL buckets, `regr_slope`, recent-vs-baseline ratio, spikes by median absolute deviation), `find_episodes`, `rank_recurring`.
2. `sql/40_episodes.sql`: episodes for BGL alert lines at 60 s, 300 s and 3,600 s gaps, at node and midplane scope; instance-scoped episodes for OpenStack WARNING and ERROR lines.
3. Tool descriptions to the contract (when to use, when not, inputs with examples, outputs, limits), annotations, resources, the three role prompts.
4. Golden tests: the `sql-verifier` subagent writes independent SQL for ten tool outputs; `pytest` compares.
5. `scripts/mcp_smoke.py` calls every tool through the SDK client.
6. Run the three role prompts on real questions, in Claude Desktop (from the exhibit connector's prompt list) and in Claude Code (as /mcp\_\_exhibit\_\_engineer\_investigate and so on). Fix wrong tool choices by editing descriptions, not by adding tools.
7. `/judge`, then tag `v0.1`.

**Acceptance (the brief's minimal requirements)**

- [ ] One answer per role, each with relevant evidence, fitting detail and a role-specific next step.
- [ ] Retrieval and aggregation on both datasets; at least one full-text answer; at least one whole-corpus aggregation per dataset or team, with scope and filters stated.
- [ ] The executed SQL and results behind every number are visible (evidence block and ledger).
- [ ] Claude picks the expected tools in three of three role runs.
- [ ] Draft README setup steps work from a clean clone.

**If it slips:** fold `rank_recurring` into `count_by(group_by=alert_category)` plus `find_episodes`, and keep the H16 gate.

### Stage 4 — Insight tools (H16–H22)

**Goal.** The tools that turn descriptive answers into insight.

**Claude Code does**

1. `what_changed`: the significant-terms pattern from the SereneDB cookbook (foreground = focus window, background = baseline window, `min_fg` floor), plus a signature shift table (observed vs expected count per alert category).
2. `metric_stats` for OpenStack: latency percentiles by endpoint, status and service; spawn and build distributions; create-to-start delay per instance via conditional `MIN(CASE …)`; `/servers/detail` polls per instance window; outliers by interquartile range and robust z.
3. `prioritize_risks`: one SQL statement with CTEs that computes per-signature features across both datasets, documented default weights, a factor breakdown per row.
4. `verify_evidence`: re-run the stored SQL with the stored parameters, compare hashes, report drift.
5. Optional, if under 45 minutes: `trend` also returns a PNG chart as MCP image content.
6. Prompt tuning: three questions per role; log misses in `evals/notes.md`; fix descriptions.
7. Before stepping away: start long jobs (the OTel remote count and one remote aggregation from Section 9c steps 1–2, heavy episode builds, the first eval batch).

**Acceptance**

- [ ] `what_changed` on a known burst returns terms with lift above 1 and foreground counts at or above the floor, verified by `sql-verifier`.
- [ ] `metric_stats` p95 latency matches an independent `percentile_cont` query.
- [ ] `prioritize_risks` lists every factor and the formula.
- [ ] `verify_evidence` returns `match` for every ID in the latest transcript.

### Stage 5 — Story and worked investigation (H27–H32)

**Goal.** One real, verified investigation shown through all three roles (method in Section 8).

**Claude Code does**

1. Run the story-mining queries from Section 8, score the candidates, pick one, log the decision.
2. Fill the question bank with real values.
3. Run the three role sessions in Claude Desktop (screenshots for slides) and headless in Claude Code for full tool-call transcripts. Headless runs start in an empty temp directory with only our server (`evals/mcp.exhibit.json` declares just `exhibit`, with an absolute `uv --directory` path), so the agent cannot fall back on the repo's `CLAUDE.md`, Bash or `psql`: `claude -p "<question>" --strict-mcp-config --mcp-config <repo>/evals/mcp.exhibit.json --allowedTools "mcp__exhibit" --disallowedTools "Bash" "Edit" "Write" "WebFetch" "WebSearch" --output-format stream-json --verbose` (check flags with `claude --help`).
4. `exhibit export --session <id> --out investigations/01-<slug>/`: per-role answer, tool-call sequence, and every evidence record (SQL, parameters, results, plan excerpt) as Markdown.
5. `/verify` on the investigation: the subagent recomputes every number with fresh SQL; fix each mismatch.
6. Validation section: BGL labels and the OpenStack anomaly labels against our tools, kept out of the agent's reach.

**Acceptance**

- [ ] The investigation README shows, for all three roles, the question, tool calls, executed SQL, results, answer and recommended action, with both search evidence and aggregation.
- [ ] A “What the data does and does not establish” section is present.
- [ ] The verifier report shows every number matching.

### Stage 6 — Bonus tracks (H32–H38)

**Goal.** Optional extensions in priority order, each stopped at its time box (details in Section 9). The boxes add up to 9.5 hours: solo, the six hours fit tracks 1, 2 and 4 plus steps 1–2 of track 3; the rest needs a teammate or time saved earlier.

1. Workspace indexes and their benchmark — 2 h.
2. Role-scoped access with `GRANT` — 1.5 h.
3. Huge data: OTel scale ladder, zero-ETL index, `trace_timeline` — 2.5 h (long parts started in Stage 4).
4. Eval harness report — 1 h.
5. Evidence board as an MCP App, or PNG charts — 1.5 h, only if 1–4 are done.
6. Packaging: `.mcpb` bundle and streamable HTTP with a bearer token — 1 h.

**Acceptance:** every finished track has a page in `bench/` or `docs/` with measured numbers and the exact commands to reproduce them.

### Stage 7 — Hardening and docs (H38–H44)

**Claude Code does**

1. Clean-checkout test: fresh clone into a temp directory, new virtualenv, fresh Docker volume, then `make setup db load bootstrap test smoke`. Fix anything that leaned on local state. The SereneDB image tag stays pinned in the Makefile so judges run the version we tested.
2. README (structure in Section 10); `docs/tools.md` generated by `scripts/gen_tools_md.py` from the live server's tool list; `docs/architecture.md`; `docs/limitations.md`; citations.
3. Freeze schema names and environment variables; complete `.env.example`.
4. `/judge`; fix the top five gaps.

**Acceptance**

- [ ] A fresh Claude Code session with no context follows the README alone and gets a cited answer within 10 minutes.
- [ ] All tests green; tag `v1.0-rc`.

### Stage 8 — Demo and submission (H44–H48)

1. Slides and demo script (Section 10); three timed rehearsals.
2. Record a backup video of the full demo.
3. Run the submission checklist and submit by H46; H46–H48 is buffer.

**Acceptance**

- [ ] Demo at or under 5:00 in three rehearsals.
- [ ] Public repo, final README, slides and video linked, tag `v1.0`.

## 8. Worked investigation: finding and proving the story

Pick the story from the data, not from memory: run six mining queries, score the candidates on a rubric, then run all three roles on the winner and verify every number. Three candidates are pre-registered as hypotheses to test first; none is assumed true.

**Story-mining queries (Stage 5, saved in `sql/stories/`)**

1. **Loud vs chronic.** Per alert category: lines, episodes (5-minute gap, midplane scope), distinct nodes, active days. Many lines in few episodes means a storm; many episodes means a chronic problem.
2. **Bursts.** Top 20 hours by alert lines with their category mix; robust z per category per day.
3. **Spatial concentration.** Share of each category's lines from its top one and top three node cards. High concentration points to local hardware; low points to something system-wide.
4. **Precursors.** For each signature pair (A, B), how often a B episode starts within 10 minutes after an A episode on the same midplane, against the count expected by chance (A's episode rate × window × B's episodes). Report lift and median lag. Build with `ASOF JOIN` or a bounded self-join on `episodes`.
5. **Cross-team chains.** Precursor pairs whose A and B belong to different owning teams. These carry the team-lead and manager stories.
6. **OpenStack timing.** Create-to-start delay and `/servers/detail` polls per instance; the top outliers.

**Pre-registered candidates (hypotheses to test)**

| Candidate | Why it could be strong | Accept if |
| --- | --- | --- |
| A. Infrastructure failure followed by job failures (BGL) | A chain from one component to another spans two owning teams, which gives every role something different to do. Check `exhibit://glossary/bgl` for filesystem, I/O-node and job-control categories first. | Precursor lift ≥ 3, ≥ 10 co-occurring episodes, a consistent lag |
| B. Hardware hotspot (BGL) | A large category concentrated on a few node cards is a clean engineer story and a clear manager action. | Top three node cards hold ≥ 50% of a category's lines while its episodes recur on ≥ 5 days |
| C. Slow provisioning (OpenStack) | Published analysis found the labelled failures show large create-to-start delays and extra polling. | Delay outliers stand out against the normal files' distribution (labels checked only afterwards) |

**Pick rubric (1–5 each; highest total wins)**

| Criterion | What a 5 looks like |
| --- | --- |
| Engineer timeline | A first failure with a clear before and after on one location |
| Team-lead pattern | Recurs over weeks with a measurable trend |
| Ownership | Involves two or more teams or components |
| Evidence mix | Needs both full-text search and whole-corpus aggregation |
| Non-obvious finding | A lift, a concentration or a timing outlier a keyword search would miss |
| Demo fit | Tellable in 60 seconds per role |

If A wins, use C as the aggregation-heavy second act on OpenStack. If no BGL candidate clears its bar, lead with C and use B's concentration analysis for the team lead.

**Structure of `investigations/01-<slug>/README.md`**

1. Summary: one paragraph per role.
2. Scope: datasets, resolved time range, filters, rows in scope.
3. Engineer, Team lead, Manager — each with the question, a tool-call table (`#`, tool, key parameters, evidence ID, result in one line), key evidence excerpts, the answer in the contract format, the recommended action.
4. What the data establishes, and what it does not.
5. Validation against labels (separate; the agent never saw them).
6. Evidence index: every ID with a link to its SQL and result file.
7. Reproduce: the exact commands.

**What the logs can and cannot establish (draft for the README)**

| Established by the logs | Not established by the logs |
| --- | --- |
| How many lines and episodes, where, when, in what order | Root cause: no hardware diagnostics, configuration or code |
| Which components and teams emit them, and the trend | Impact on jobs, users or customers; downtime; cost |
| Co-occurrence and lag between signatures | Causation: co-occurrence with lift is a lead, not proof |
| Timing distributions (latency, spawn, create-to-start) | How the OpenStack failures were injected |

**Validation method (kept out of the agent's reach)**

- **BGL, label-free detection.** Run spike detection on ERROR-and-above lines without using labels. Report precision (share of detected spike hours that contain labelled alerts) and recall (share of labelled alert episodes inside detected hours).
- **BGL, lines vs incidents.** Report labelled alert lines against episodes at 1, 5 and 60 minutes. This shows how far raw counts overstate incidents.
- **OpenStack.** Rank all instances by create-to-start delay without labels, then report where the four labelled instances land.

## 9. Bonus tracks

The strongest bonus story merges two optional items: the agent builds a temporary index over just the incident window of a 1-billion-row remote Parquet file, investigates, measures the trade-off and drops the index. Build the tracks in the order below and stop each at its time box.

### 9a. Agent-managed workspace indexes (2 h)

**Probe first (team measurement, 17 Oct).** On 26.09.1.3 a partial inverted index showed no effect: the planner did not pick it, a count against it ignored its predicate (121,498 where the table returns 0), and timings were equal (4.19 ms vs 3.99 ms). Re-probe before spending time here. If it still shows nothing, build the workspace as a window table with its own inverted index (§12), which is a real index for a selected time range, and report the partial-index result as measured: the brief asks for the time comparison and the trade-off, and an honest negative result answers it. Sizes come from the data directory, because no SQL metric reports them.

- `workspace_create_index(dataset, time_from, time_to, label)` runs `CREATE INDEX ws_<shortid> ON <table or view> USING inverted (…) WHERE ts >= '<t1>' AND ts < '<t2>'`. DDL cannot take bind parameters, so timestamps are parsed in Python and re-formatted; nothing from the user is pasted raw.
- Track every workspace in `exhibit_workspace` (name, dataset, window, created, TTL, build ms, size). Only names in that table can be dropped; at most three live at once; a TTL sweep runs at server start and on each call.
- `workspace_benchmark`: five query shapes (phrase, any words, fuzzy, facet count, hourly trend) × five repeats × three modes (table scan with `LIKE` under the same time filter, the full index, the workspace index). Report p50 and p95, first-run vs warm, and break-even = build time ÷ (scan time − workspace time).
- Expect, and say plainly: when a full index already exists, a workspace index adds little. It pays where no full index exists, which is the remote lake. Lead the demo with that case.

### 9b. Role-scoped access with GRANT (1.5 h)

- `sql/50_roles.sql` creates `exhibit_engineer`, `exhibit_lead`, `exhibit_manager` with passwords from the environment.
- Engineer: `SELECT` on the derived tables and their indexes.
- Team lead: one view per team (`v_lead_<team>`: rows whose `team` matches), generated from the ownership table; if grants on index relations work (probe it), add a partial index per team.
- Manager: `v_rollup_daily` (date, dataset, team, alert category, level, lines) and column grants that exclude `content`.
- `EXHIBIT_ROLE=engineer|lead|manager` picks the database credentials for the MCP server; tools refused by the database return a helpful “not permitted for this role” message.
- Demo proof: `SET ROLE exhibit_manager; SELECT content FROM bgl_ev LIMIT 1;` → permission denied. Framing: row security policies are not in SereneDB yet (issue #212), so access follows its documented model of views and grants.

Every role also needs `USAGE` on our schema and `INSERT` / `SELECT` on `exhibit_evidence`, or the ledger and `verify_evidence` fail under that role; the login that runs the MCP server must be a member of each role it switches to with `SET ROLE`.

### 9c. Huge datasets: the OTel scale ladder (2.5 h, long parts started in Stage 4)

1. Metadata count of one file: `SELECT count(*) FROM read_parquet('https://public-pme.s3.eu-west-3.amazonaws.com/text_bench/part_000.parquet')`.
2. Column-pruned aggregate over that file: `SELECT ServiceName, SeverityText, count(*) … GROUP BY ALL`, first run and warm run.
3. Ten files (10B rows) through an `s3://public-pme/text_bench/part_00*.parquet` glob if anonymous listing works with region `eu-west-3`; otherwise stop at one file and say why.
4. Time-sliced view over one file. Files are sorted by timestamp, so `WHERE "Timestamp" < '<start + N minutes>'` should prune row groups. Index it: `USING inverted ("Body" log_text, "ServiceName", "SeverityText", "SeverityNumber", "Timestamp", "TraceId") INCLUDE ("SpanId")`. Pilot N = 3 minutes, measure rows per second of build, extrapolate before going larger. TraceId is indexed rather than INCLUDEd, because INCLUDE columns are stored but cannot be searched; quote the mixed-case names, since unquoted identifiers fold to lowercase.
5. Register `otel` in `datasets.py` and run the same tools: search (borrow TextBench-style queries such as “connection reset” and “failed order”), `count_by` service, a per-minute `trend`, `find_episodes` per service.
6. `trace_timeline(trace_id)` from a search hit: every log line of one request across services, in time order. It is a log-side view; real logs-to-traces correlation needs span data (9g).
7. For every step record rows in scope (exact), files touched, first-run and warm time, index build time and `sdb_metrics` size, and the machine's CPU, RAM and disk. Cost: the bucket is public, so nothing is billed to us; report bytes read and files touched as the cost proxy where EXPLAIN ANALYZE shows them; say “not measured” rather than guess.

Indexing runs on our own machine; the organizers provide no extra infrastructure, and only the index is stored locally (a snapshot, refreshed with `REINDEX INDEX`). Start with the 3-minute slice, scale to what the laptop holds, and report how much data was actually queried and how long it took. Results go to `bench/scale_ladder.md` and one slide. If remote Parquet is blocked, a larger Loghub dataset (Thunderbird, 211M lines; Windows, 114M lines) is the other route; it needs a download, so check disk first.

### 9d. Eval harness (1 h)

- `evals/questions.yaml`: 12 questions (four per role), each with the expected tool set and golden SQL for its key numbers.
- Runner: headless Claude Code per question from an empty temp directory with only our server (`--strict-mcp-config --mcp-config evals/mcp.exhibit.json --allowedTools "mcp__exhibit"`, built-in tools disallowed as in Stage 5), so the scores measure our tools and not Bash; parse tool-use events from the stream-JSON output.
- Scores: tool selection (expected tools used, extra calls counted), numeric accuracy (golden value present within tolerance), contract (all seven contract sections; manager lint), latency and number of calls.
- `evals/REPORT.md`, re-run after every tool-description change as a regression check.

### 9e. Evidence board (1.5 h, only if 9a–9d are done)

- Best: an MCP App. A tool `open_evidence_board(evidence_ids)` declares `_meta.ui.resourceUri = "ui://exhibit/board"`; the resource (`text/html;profile=mcp-app`) renders the timeline, trend and evidence table inline in Claude, with a plain-text fallback.
- Cheaper: `trend(..., chart=true)` returns a PNG as MCP image content.

Gotcha: Claude is strict about the MCP Apps handshake. The page must send `ui/initialize` with `appInfo`, `appCapabilities` and `protocolVersion: "2026-01-26"`, then `ui/notifications/initialized`, or the frame stays blank. Tell the model the board is open only if the client declared the `io.modelcontextprotocol/ui` capability.

### 9f. Packaging (1 h)

- `.mcpb` Desktop Extension: `npx @anthropic-ai/mcpb init`, a Python server entry, `user_config` for host, port, user and a sensitive password, `mcpb pack`; test with a double-click install.
- Streamable HTTP: `--transport streamable-http --port 8000` with a bearer-token check; Claude Code connects with `claude mcp add --transport http exhibit http://<host>:8000/mcp --header "Authorization: Bearer <token>"`. Host it publicly only if the organizers allow outside services.

MCPB is built around Node servers, which Claude Desktop ships a runtime for; a Python server needs Python or `uv` on the judge's machine. Check the manifest spec's server types before investing, and keep the JSON config as the primary install path.

### 9g. Logs + metrics + traces (stretch, only if far ahead)

Start with Nezha: its Train Ticket application logs already carry trace IDs, so once logs and traces are loaded with SereneDB's file readers, the log-to-trace link is a single `JOIN`. Then one RCAEval RE2 case (logs, metrics and traces for one injected fault) loaded with `read_csv`: show the tools pointing at the faulty service from error logs, a metric spike and trace latency, then compare with the case's label. HDFS\_v3 (TraceBench) is the in-Loghub alternative. Skip all of it without regret: the OTel `TraceId` timeline is a per-request log view, while only these datasets give real correlation of logs with traces and metrics.

## 10. Demo, slides and submission

The demo proves the thesis in five minutes: three roles answered with visible tool calls in a recorded video (plus a 3-minute cut), every cited number re-verified on screen, then one minute of depth. Rehearse twice against a timer before recording.

**Run of show (5:00)**

| Time | Screen | What happens |
| --- | --- | --- |
| 0:00–0:25 | Title slide | “Three people, same logs, different decisions. Our rule: no number without a query.” |
| 0:25–1:35 | Claude Desktop, `/engineer_investigate` | Tool calls stream: `search_logs` → `get_context` → `what_changed` → `find_episodes`. Open one evidence ID: the SQL and the `IRESEARCH_SCAN` plan line. |
| 1:35–2:30 | `/team_lead_review` | `rank_recurring` + `trend`: “N lines but only M episodes, rising against baseline, owned by team T; investigate first because …” |
| 2:30–3:20 | `/manager_brief` | Risk register; read the “Not established” box aloud; the decision and its owner. |
| 3:20–3:40 | `verify_evidence` on all cited IDs | Every ID returns `match`. |
| 3:40–4:30 | Depth slides | Lines vs episodes at three gaps; validation against labels; workspace index on the 1B-row lake with break-even; scale ladder; eval pass rates. |
| 4:30–5:00 | Closing slide | Connect in one line, known limitations, repo link. |

Prompt names differ by client: Claude Code lists them as `/mcp__exhibit__engineer_investigate` and so on; Claude Desktop lists them under the exhibit connector. Rehearse both by H16.

**Backups:** a recorded video of the full run; cached transcripts in `investigations/`; the loaded and indexed Docker volume left untouched, so the demo never waits on a reload.

**Slides (10)**

1. Title and thesis.
2. Three roles, three decisions: what each person needs from the same logs.
3. Architecture.
4. The tools and the response contract.
5. Worked investigation: one card per role.
6. Evidence and verification: ledger entry, SQL, plan line, `match`.
7. Lines are not incidents, plus validation against labels.
8. Scale ladder and workspace-index trade-off.
9. Limitations and next steps.
10. Links and citations (Loghub, Oliner & Stearley, the OTel demo corpus published by ClickHouse under Apache-2.0, SereneDB docs).

**README outline**

1. One-paragraph pitch and a screenshot.
2. Judge quickstart in at most ten commands: prerequisites (Docker, `uv`), clone, `make setup`, `make db` (SereneDB in Docker with `data/` mounted), `make load` (downloads BGL and OpenStack from Zenodo and loads them with our loader), `make bootstrap`, connect Claude, try the three prompts.
3. Ten example questions across the roles.
4. Workflow: question → tool → SQL → evidence → answer.
5. Tools (generated from the live server).
6. Worked investigation (link).
7. Data scope, derived fields and ownership coverage.
8. Benchmarks and eval results.
9. Access model and security notes.
10. Known limitations.
11. Citations and licence.

**Four ways for judges to connect**

- Claude Code in the repo: `.mcp.json` is picked up automatically; approve it when prompted.
- Claude Code anywhere: `claude mcp add exhibit -- uv --directory /ABSOLUTE/PATH/exhibit run exhibit-mcp`.
- Claude Desktop: add to `claude_desktop_config.json`, using the absolute path that `which uv` prints, because Desktop does not inherit your shell's `PATH`:

```json
{
  "mcpServers": {
    "exhibit": {
      "command": "/ABSOLUTE/PATH/TO/uv",
      "args": ["--directory", "/ABSOLUTE/PATH/exhibit", "run", "exhibit-mcp"],
      "env": {
        "SERENEDB_HOST": "localhost", "SERENEDB_PORT": "7890",
        "SERENEDB_USER": "<user>", "SERENEDB_PASSWORD": "",
        "SERENEDB_DB": "<db>"
      }
    }
  }
}
```

- Optional: double-click `exhibit.mcpb`, or point any client at the streamable HTTP endpoint.

**Submission checklist**

- [ ] Repo public; README quickstart verified from a clean clone; `.env.example` complete; no secrets in git history.
- [ ] `docs/tools.md` generated; `investigations/01-*` complete with evidence; `docs/limitations.md`.
- [ ] Slides and video linked in the README; demo at or under five minutes.
- [ ] Dataset citations in README and slides.
- [ ] Tag `v1.0`; submission form sent before the deadline.
- [ ] Reproducible from scratch: schema, loader and ownership table in the repo; `make db load bootstrap` documented in the README with the pinned SereneDB image.
- [ ] Public face: build files (`PLAN.md`, `KICKOFF.md`, `PROGRESS.md`) moved to `docs/process/`; the root `CLAUDE.md` replaced by a short judge version (what the tools do, the three prompts, cite evidence IDs); `.claude/settings.json` trimmed to read-only rules.
- [ ] MIT licence and a disclosure section: models and tools used, and what was built during the window.
- [ ] Video of at most 5 minutes, plus a 3-minute cut, with real queries and real numbers on screen.
- [ ] SereneDB starred on GitHub and the docs MCP connected (listed prerequisites).

## 11. Risks, fallbacks and cut lines

The biggest risk is not a bug but a late MVP: protect the H16 gate, and cut features before cutting verification. Each risk below has an early signal and a prepared fallback.

| Risk | Early signal | Fallback |
| --- | --- | --- |
| A SereneDB feature we rely on fails on our instance | FAIL in `docs/capabilities.md` at H1 | Alternative SQL (bounded self-join instead of `ASOF JOIN`; `GROUP BY` instead of `ts_dict_agg`), or Python over already-aggregated rows, never over raw samples |
| Schema, loader and ownership table are ours to write | Settled by the Q&A of 17 Oct | Loader in Stage 0 (raw lines in, parsing in SQL); ownership table as a documented, fictional mapping in `seed/ownership.csv` |
| Laptop too slow or short of memory for 4.7M-line indexes | Measured 17 Oct on 2 vCPU / 12 GB: derive 14 s, `bgl_idx` 5.2 s, full rebuild about 20 s | Retired; watch memory only in the OTel bench |
| Tokenizer splits node IDs, hex values or UUIDs badly | `ts_lexize` results in Stage 1 | Keep IDs in keyword columns; add a second dictionary for the message text |
| MCP SDK v2 friction | Stuck for 30 minutes | Pin `mcp[cli]>=1.28,<2` and use FastMCP |
| Claude picks the wrong tools or loops | Misses in role runs and evals | Sharpen “when to use / when not”, add `next_suggested_tools`, merge overlapping tools |
| A number in an answer does not hold | `verify_evidence` drift or verifier mismatch | Mandatory verification in the prompts; demo only from verified transcripts |
| No BGL story clears its bar | Stage 5 rubric | Lead with the OpenStack timing story (candidate C) |
| Remote Parquet too slow for the instance | Steps 1–2 of the scale ladder | Stop at one file or a time slice; report what was measured |
| Network fails during the demo | — | Recorded video; local Docker with the same data |
| Instructions hidden in log text steer the agent | Theoretical, but judges may ask | Log text returned as data in a `message` field; server instructions; no write tools by default |
| The server cannot see local files | `read_csv` reports a missing file | Mount `data/` into the container (`-v "$PWD/data":/data`) and read `/data/…` paths; or load through `COPY … FROM STDIN` |
| Fatigue (solo) | Mistakes after H20 | Sleep H22–H27 with long jobs running; stop coding at H44 |
| Judges cannot reproduce the setup | The Stage 7 clean-clone test | `make db load bootstrap` from a fresh clone; pinned SereneDB image tag; the README states the download size and load time |

**Cut lines**

- **H16 without an end-to-end answer per role:** drop `what_changed`, `metric_stats` and `prioritize_risks` (the manager uses `count_by` + `trend` + `find_episodes`) and all of Stage 6 except 9a; put the saved time into Stage 5.
- **H32 and behind:** drop 9c after step 2, plus 9e, 9f and 9g; keep 9a and a six-question version of 9d.
- **H40 and behind:** feature freeze; only docs, verification and demo.

**Never cut:** the evidence ledger, the verification step, the worked investigation, the clean-clone quickstart, the rehearsals.

## 12. Appendix: SereneDB SQL cheat sheet

These patterns follow the SereneDB docs as read on 16 October 2026; column names assume the Section 4 data model. Treat each as a starting point: the team's docs/capabilities.md, the Stage 0 probe and the docs MCP server are the final word, and every statement that takes user input uses bind parameters.

**Discover functions**

```sql
SELECT DISTINCT function_name, function_type FROM sdb_functions()
WHERE function_name LIKE 'ts_%' ORDER BY 1;
```

**Dictionary, index, refresh**

```sql
-- Form measured on 26.09.1.3; the AS split_text(...) form is a syntax error there
CREATE TEXT SEARCH DICTIONARY log_text (
  template = 'text', locale = 'en_US.UTF-8', case = 'lower',
  stemming = false, accent = false, frequency = true, position = true);
SELECT ts_lexize('log_text', 'R02-M1-N0-C:J12-U11 ciod: failed to read message prefix');

CREATE INDEX bgl_idx ON bgl_ev
  USING inverted (id, content log_text, ts, level_rank, alert_category,
                  component, level, node, node_kind, rack, midplane,
                  nodecard, team, template_id)
  WITH (optimize_top_k = 'bm25(1.2, 0.75)');
VACUUM (REFRESH_TABLE) bgl_ev;
```

**Search: ranked, time-filtered, highlighted, with an exact total**

```sql
SELECT id, ts, node, component, level,
       ts_highlight(content, ts_offsets(bgl_idx.content)) AS snippet,
       BM25(bgl_idx.tableoid) AS score
FROM bgl_idx
WHERE content @@ ts_phrase(%(phrase)s)
  AND ts BETWEEN %(t1)s AND %(t2)s        -- or: ts @@ ts_between(%(t1)s, %(t2)s, true, false)
ORDER BY score DESC, id
LIMIT 20;

SELECT count(*) FROM bgl_idx
WHERE content @@ ts_phrase(%(phrase)s) AND ts BETWEEN %(t1)s AND %(t2)s;
```

**Search modes → query constructors**

| `match` | Predicate |
| --- | --- |
| `any` | `content @@ ts_any(%(words)s)` |
| `all` | `content @@ ts_all(%(words)s)` or `plainto_tsquery(%(text)s)` |
| `phrase` | `content @@ ts_phrase(%(text)s)` |
| `near` | `content @@ ('lustre' ## [0, 3] ## 'failed')` (built from validated single tokens) |
| `fuzzy` | `content @@ ts_levenshtein(%(word)s, 1)` |
| `prefix` | `content @@ ts_starts_with(%(prefix)s)` |
| `lucene` | `content @@ to_tsquery(%(query)s)` |

**Facets over all matches (term dictionary, no document scan)**

```sql
SELECT unnest(ts_dict_agg(component))   AS component,
       unnest(ts_dict_count(component)) AS lines
FROM bgl_idx
WHERE content @@ ts_phrase(%(phrase)s);
```

**Significant terms: focus window vs baseline window**

```sql
WITH fg AS (
  SELECT unnest(ts_dict_agg(content)) AS term, unnest(ts_dict_count(content)) AS fg_docs
  FROM bgl_idx WHERE ts BETWEEN %(f1)s AND %(f2)s AND midplane = %(mp)s),
bg AS (
  SELECT unnest(ts_dict_agg(content)) AS term, unnest(ts_dict_count(content)) AS bg_docs
  FROM bgl_idx WHERE ts BETWEEN %(b1)s AND %(b2)s AND midplane = %(mp)s),
t AS (
  SELECT (SELECT count(*) FROM bgl_idx WHERE ts BETWEEN %(f1)s AND %(f2)s AND midplane = %(mp)s) AS fg_total,
         (SELECT count(*) FROM bgl_idx WHERE ts BETWEEN %(b1)s AND %(b2)s AND midplane = %(mp)s) AS bg_total)
SELECT fg.term, fg_docs, coalesce(bg_docs, 0) AS bg_docs,
       round(fg_docs - coalesce(bg_docs, 0) * t.fg_total::DOUBLE / t.bg_total, 2) AS excess,
       round((fg_docs::DOUBLE / t.fg_total) / ((coalesce(bg_docs, 0) + 1)::DOUBLE / t.bg_total), 2) AS ratio
FROM fg LEFT JOIN bg USING (term) CROSS JOIN t
WHERE fg_docs >= 3
ORDER BY excess DESC
LIMIT 15;
```

**Episodes: gap-based coalescing**

```sql
WITH a AS (
  SELECT id, ts, alert_category AS sig, midplane, node, level_rank
  FROM bgl_ev WHERE is_alert),
m AS (
  SELECT *, CASE WHEN LAG(ts) OVER (PARTITION BY sig, midplane ORDER BY ts, id) IS NULL
                   OR ts - LAG(ts) OVER (PARTITION BY sig, midplane ORDER BY ts, id) > INTERVAL '5 minutes'
              THEN 1 ELSE 0 END AS new_ep
  FROM a),
n AS (
  SELECT *, SUM(new_ep) OVER (PARTITION BY sig, midplane ORDER BY ts, id
                              ROWS UNBOUNDED PRECEDING) AS ep
  FROM m)
SELECT sig, midplane, ep, min(ts) AS start_ts, max(ts) AS end_ts,
       count(*) AS lines, count(DISTINCT node) AS nodes, max(level_rank) AS max_level
FROM n
GROUP BY sig, midplane, ep;
```

**Weekly trend with slope and recent-vs-baseline rate** (fill empty weeks with `generate_series` first, or zero weeks vanish and the slope lies)

```sql
WITH b AS (
  SELECT date_trunc('week', ts::timestamptz) AS wk, count(*) AS n
  FROM bgl_ev WHERE alert_category = %(cat)s GROUP BY 1),
i AS (
  SELECT wk, n, row_number() OVER (ORDER BY wk) AS k, count(*) OVER () AS kmax FROM b)
SELECT regr_slope(n, k) AS slope_per_week,
       sum(CASE WHEN k > kmax - 4 THEN n END) / 4.0 AS recent_rate,
       sum(CASE WHEN k <= kmax - 4 THEN n END)::DOUBLE / greatest(max(kmax) - 4, 1) AS baseline_rate
FROM i;
```

**Context around an event**

```sql
SELECT id, ts, node, level, content
FROM bgl_idx
WHERE midplane = %(mp)s
  AND ts BETWEEN %(t)s - INTERVAL '5 minutes' AND %(t)s + INTERVAL '5 minutes'
ORDER BY ts, id
LIMIT 200;
```

**OpenStack: latency percentiles and create-to-start delay**

```sql
SELECT endpoint, count(*) AS n,
       percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_s) AS p50,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_s) AS p95,
       max(latency_s) AS max_s
FROM os_ev WHERE latency_s IS NOT NULL
GROUP BY endpoint ORDER BY p95 DESC;

SELECT instance_id,
       extract(epoch FROM min(CASE WHEN content LIKE '%%VM Started%%' THEN ts END))
     - extract(epoch FROM min(CASE WHEN content LIKE '%%Creating image%%' THEN ts END)) AS create_to_start_s
FROM os_ev WHERE instance_id <> 'NONE'
GROUP BY instance_id
ORDER BY create_to_start_s DESC NULLS LAST
LIMIT 20;
```

**Workspace index lifecycle**

```sql
-- 1. Partial index: documented, but no effect measured on 26.09.1.3. Re-probe before use.
CREATE INDEX ws_a1b2_p ON bgl_ev
  USING inverted (id, content log_text, ts, node, midplane)
  WHERE ts >= TIMESTAMP '2005-11-01 00:00:00' AND ts < TIMESTAMP '2005-11-02 00:00:00';

-- 2. Fallback: a window table with its own index, a real index for one time range
CREATE TABLE ws_a1b2_t AS
  SELECT * FROM bgl_ev
  WHERE ts >= TIMESTAMP '2005-11-01 00:00:00' AND ts < TIMESTAMP '2005-11-02 00:00:00';
CREATE INDEX ws_a1b2 ON ws_a1b2_t
  USING inverted (id, content log_text, ts, node, midplane);
VACUUM (REFRESH_TABLE) ws_a1b2_t;
-- size: no SQL metric; compare the data directory (du -sh) before and after

DROP INDEX ws_a1b2; DROP TABLE ws_a1b2_t; DROP INDEX ws_a1b2_p;
```

**Zero-ETL over remote Parquet** (`part_000` holds the first 30 minutes; TextBench's queries suggest 2025-09-23 00:00–00:30, so confirm with `min`/`max` first; quote the mixed-case column names, because unquoted identifiers fold to lowercase)

```sql
CREATE VIEW otel_slice AS
  SELECT * FROM read_parquet('https://public-pme.s3.eu-west-3.amazonaws.com/text_bench/part_000.parquet')
  WHERE "Timestamp" < TIMESTAMP '2025-09-23 00:03:00';

CREATE INDEX otel_slice_idx ON otel_slice
  USING inverted ("Body" log_text, "ServiceName", "SeverityText", "SeverityNumber",
                  "Timestamp", "TraceId")
  INCLUDE ("SpanId");

SELECT "ServiceName", count(*) AS lines
FROM otel_slice_idx
WHERE "Body" @@ ts_all(['connection', 'reset'])
GROUP BY 1 ORDER BY 2 DESC;
```

**Role scope without row-security policies**

```sql
CREATE ROLE exhibit_manager LOGIN PASSWORD 'from-env';
CREATE VIEW v_rollup_daily AS
  SELECT date_trunc('day', ts::timestamptz) AS day, team, component, alert_category, level, count(*) AS lines
  FROM bgl_ev GROUP BY ALL;
GRANT USAGE ON SCHEMA exhibit TO exhibit_manager;
GRANT SELECT ON v_rollup_daily TO exhibit_manager;
GRANT INSERT, SELECT ON exhibit_evidence TO exhibit_manager;  -- ledger and verify_evidence
GRANT exhibit_manager TO <server_login>;                      -- membership, so SET ROLE works

SET ROLE exhibit_manager;
SELECT content FROM bgl_ev LIMIT 1;   -- expected: permission denied
RESET ROLE;
```

**Gotchas** (the team's measurements on 26.09.1.3 win; see Section 0): the dictionary takes the parenthesised form, not `AS split_text(…)`; `@@` only against an index relation, never the table; `ts_highlight` and `ts_offsets` need an `@@` in the same sub-query; timestamps arrive as `VARCHAR`, so cast them, and `date_trunc` needs `::timestamptz`; `to_timestamp(text)`, `to_char` and `to_date` do not exist, so use `::timestamp` or `strptime`; wrap `regexp_extract` in `NULLIF(…, '')`; `VARCHAR(n)` is accepted but not enforced; never support a count with `LIKE`, and always state the operator; no SQL metric reports index size; refresh after loads; keep facet columns `NOT NULL`; integer division truncates, so cast shares, lifts and ratios to `DOUBLE`; unquoted identifiers fold to lowercase; `UUID`, `DECIMAL`, `HUGEINT` and `INTERVAL` columns cannot be indexed; `INCLUDE` columns cannot be searched; in psycopg, a literal `%` is written `%%` when the statement has parameters.

## 13. Sources

Pages opened while preparing this plan, as of 16 October 2026.

**Challenge**

- “Making Sense of Logs: The Right Insights for the Right People” — SereneDB challenge brief, National AI Hackathon 2026 by SchubKI (PDF from the organizers), and their participant Q&A of 17 October 2026 (local setup; optional huge datasets).

**SereneDB**

- [Quick Start](https://serenedb.com/docs/quick-start) · [Inverted Index](https://serenedb.com/docs/sql/indexes/inverted) · [Full-Text Search](https://serenedb.com/docs/sql/indexes/inverted/full-text-search) · [Ranking](https://serenedb.com/docs/sql/indexes/inverted/ranking) · [Text Analysis](https://serenedb.com/docs/sql/indexes/inverted/text-analysis)
- [Indexing Views](https://serenedb.com/docs/sql/indexes/inverted/views) · [Indexing External Data](https://serenedb.com/docs/sql/indexes/inverted/external-data) · [Maintenance & Introspection](https://serenedb.com/docs/sql/indexes/inverted/maintenance)
- [Term Dictionary](https://serenedb.com/docs/sql/functions/search/term-dictionary) · [Faceted Search](https://serenedb.com/docs/cookbook/search/faceted-search) · [Significant Terms](https://serenedb.com/docs/cookbook/search/significant-terms) · [AsOf Join](https://serenedb.com/docs/cookbook/sql_features/asof_join)
- [PostgreSQL Compatibility](https://serenedb.com/docs/compatibility/core-sql-compatibility) · [Security](https://serenedb.com/docs/security) · [Privileges](https://serenedb.com/docs/security/privileges) · [Functions](https://serenedb.com/docs/sql/functions)
- [Apps & Clients](https://serenedb.com/docs/clients) · [Serene Docs Search (docs MCP server)](https://serenedb.com/docs/clients/serene-docs-search) · [Benchmarks](https://serenedb.com/docs/benchmarks)
- [SereneDB repository](https://github.com/serenedb/serenedb) · [SearchBench repository](https://github.com/serenedb/searchbench)

**Data and log analysis**

- [Zhu et al., Loghub (ISSRE 2023)](https://arxiv.org/pdf/2008.06448) — dataset table, BGL label convention, and the references to Oliner & Stearley (DSN 2007) and Liang et al., “Filtering failure logs for a BlueGene/L prototype” (DSN 2005)
- [Loghub-2.0](https://github.com/logpai/loghub-2.0) — template counts for BGL and OpenStack
- [Xin, Explaining OpenStack Failure-Injection Log Anomalies (EIST, 2025)](https://journal.umy.ac.id/index.php/eist/article/view/31232)
- [ClickHouse: analytical log search benchmark on OTel logs](https://clickhouse.com/blog/elasticsearch-log-analytics-clickhouse) · [TextBench queries](https://github.com/ClickHouse/TextBench/blob/a7bb4e024f4648e90a30b6f0d00ef1223fd7d7e5/clickhouse/queries.sql) · [TextBench schema](https://github.com/ClickHouse/TextBench/blob/main/clickhouse/create.sql)

**MCP and Claude**

- [MCP Python SDK (v2)](https://github.com/modelcontextprotocol/python-sdk)
- [Build a desktop extension with MCPB](https://claude.com/docs/connectors/building/mcpb)
- [MCP Apps contract and lifecycle (nanohub-mcp reference)](https://nanohub-mcp.readthedocs.io/en/latest/skill/references/mcp-apps.html)
- [Claude Code: MCP (tool search, alwaysLoad, output limits)](https://code.claude.com/docs/en/mcp) · [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference)
