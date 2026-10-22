# Logging off Early — role-aware log intelligence on SereneDB

**National AI Hackathon 2026 · SchubKI · Track 04 — "Making Sense of Logs"**

> **Winner of Track 04, "Making Sense of Logs" (the SereneDB challenge), at the SchubKI National AI Hackathon 2026.**
>
> The version the judges saw is frozen at tag [`v1.0`](https://github.com/Arnie1x/exhibit/tree/v1.0):
> commit [`71e95ed`](https://github.com/Arnie1x/exhibit/commit/71e95ed), `main` as it stood at the
> submission deadline, 18 October 2026, 23:59 CEST. Everything after that tag was added after judging.

Two students, 48 hours, one question: *can a database plus an LLM answer the same question
three different ways — for the engineer who fixes it, the lead who has to staff it, and the
manager who has to justify the decision?*

We take BGL and OpenStack logs, index them in SereneDB, and expose them to an LLM agent
through an MCP server whose every answer is computed by SQL and cited back to the exact
query that produced it.

## Start here

| If you want | Read |
|---|---|
| **The worked investigation** — the questions, the tool calls, the executed SQL, the results, and the answers for the engineer, team lead and manager | [`docs/worked-investigation.md`](docs/worked-investigation.md) |
| **The slides** | [`docs/slides.pdf`](docs/slides.pdf) |
| **How we know it works when a stranger talks to it** — 29 judge-style questions against the live endpoint, and the eight defects they found | [`docs/battery.md`](docs/battery.md) |
| What SereneDB 26.09.1.3 actually does — one row per thing we tried, executed | [`docs/capabilities.md`](docs/capabilities.md) |
| What the corpora look like once you read them properly | [`docs/data-notes.md`](docs/data-notes.md) |
| Ground truth, scored from outside the agent | [`docs/validation.md`](docs/validation.md) |
| What we used, and what was built during the build window | [`docs/disclosure.md`](docs/disclosure.md) |

Reproduce the whole thing, then read the investigation:

```bash
make bootstrap smoke       # load + index both corpora (~20 s) and print the headline numbers
make demo                  # both worked investigations, engineer -> lead -> manager
make check eval validate   # 101 acceptance checks, 15/15 eval, 13/13 ground truth
```

The working documents we built from — the plan, the build reference, the handoff log — are in
[`docs/process/`](docs/process/), which also says which files to read instead.

## The one idea

> **SQL computes. The LLM explains.**

The model never invents a number. Every figure in every answer comes from a query result
carried in an evidence ledger, and the answer cites the evidence ID. A validation pass
rejects any answer whose numbers are not present in the tool output.

## Why our numbers look different

**Lines are not incidents.** Our corpus holds 348,460 alert lines in BGL — but only
19,250 *episodes* once you group a signature by the time gap (5 minutes) and failure domain
(midplane). Ranking by line count points at the wrong problem: `data TLB error interrupt` has
152,734 lines (44% of all alerts) but is only 117 episodes, because 152,182 of those lines
happen on one node in one 6h22m burst on 2005-06-11. Meanwhile the alert category `APPSEV`, at
49,651 lines across its five signatures, is 7,165 episodes per midplane (`bgl_signature_stats`).

Both rankings are in the demo, side by side. That is what "making sense of logs" means.

## Requirements

| Dependency | Version | Used for |
|---|---|---|
| Docker | any recent | SereneDB `serenedb/serenedb:26.09.1.3` (the image the numbers were measured on) |
| GNU make, bash | any | every target in the `Makefile` |
| Python | 3.11+ (`.python-version`) | the parser and the MCP server |
| [uv](https://docs.astral.sh/uv/) | any recent | installs `mcp>=2.3.0` and `psycopg[binary]>=3.3.6` (`pyproject.toml`, pinned in `uv.lock`); `make parse` adds `pyarrow` on the fly |
| curl, unzip, tar | any | `make fetch` |
| `psql` | optional | the SQL targets; without it, pass `PSQL='docker exec -i serenedb psql …'` (below) |
| Disk | ~1.5 GB | archives, unpacked logs, Parquet and the SereneDB volume |

## Quickstart

```bash
# 1. SereneDB (arm64: 26.09.1.3 is the newest multi-arch tag; 26.10.x is amd64-only)
docker run -d --name serenedb -p 127.0.0.1:7890:7890 \
  -e SERENEDB_HOST_AUTH_METHOD=trust \
  -v serenedb-data:/var/lib/serenedb -v "$PWD/data":/data serenedb/serenedb:26.09.1.3

# 2. Raw Loghub data (BGL + OpenStack from Zenodo record 8196385: 63 MB of archives,
#    ~800 MB unpacked into data/loghub/), then parse to Parquet (BGL 4,747,963 of 4,747,963 lines)
make fetch parse

# 3. Derive + index  (~20 seconds total: 14s derive, 5.6s index)
make bootstrap

# 4. Sanity check
make smoke

# 5. Run the MCP server against a stock client
make mcp
```

**There is no supplied loader, schema or ownership table, and no shared instance.** That is the
organisers' own guidance: you run SereneDB locally and build those three pieces yourself. So
`make fetch` pulls the corpora from Loghub (Zenodo record 8196385) and **our** loader is
`scripts/parse.py` + `sql/10_derive.sql` — BGL 4,747,963 of 4,747,963 lines, OpenStack 207,812 of
207,820 (the eight unusable lines are documented in `docs/data-notes.md`).

`psql -h 127.0.0.1 -p 7890 -U postgres` — no password, because of that one env var. **Without it
the container's default host auth demands a password even on loopback** (Docker Desktop forwards
`127.0.0.1:7890` from the bridge, which the default HBA treats as remote), and you get
`password authentication failed for user "postgres"` from a database that is, confusingly, empty of
passwords. On first start the container's entrypoint writes the `trust` HBA and says so, with the
scope warning reproduced here: trust means anyone who can reach the published port can connect as
any role, which is why the port is published to `127.0.0.1` only. This is a laptop-and-demo
setting; the repo never asks for it anywhere else. The server reads files from **its own**
filesystem, hence the `-v "$PWD/data":/data` mount; remote HTTP/S3 Parquet needs no mount.

**No `psql` on the host?** Every SQL target takes `PSQL`, so the client inside the container
does the job: `make bootstrap smoke PSQL='docker exec -i serenedb psql -h 127.0.0.1 -p 7890 -U postgres'`.
On Windows with Git Bash, also `export MSYS_NO_PATHCONV=1`, or Git Bash rewrites `/data/loghub`
into `C:/Program Files/Git/data/loghub` before Docker sees it. The Makefile sets `PYTHONUTF8=1`,
because a Windows console's default code page cannot print the checks' output.

## What is in the repository

The things to read first are in **Start here** above. This is the full map, so nothing is hidden:
the code and SQL first, the working documents last.

| Path | What it is | Status |
|---|---|---|
| `docs/process/PLAN.md` | The full build plan: stages, gates, allocation, Q&A prep — **§16 is the rule list for coding agents** | done |
| `docs/capabilities.md` | What SereneDB 26.09.1.3 actually does — every row executed | done |
| `docs/data-notes.md` | Corpus recon: BGL's four record shapes, the five findings | done |
| `sql/10_derive.sql` | Raw Parquet → `bgl_ev`, `os_ev`, `owner_map` | done, runs in 14 s |
| `sql/20_indexes.sql` | Dictionary + `bgl_idx` / `os_idx` | done, runs in 5.6 s |
| `sql/30_views.sql` | Signatures, episodes, incidents, durations | done |
| `sql/99_smoke.sql` | The headline numbers, for verification | done |
| `sql/50_roles.sql` | Role views + GRANTs: engineer, lead, manager; scope enforced in the database | done, runs in 1.4 s; part of `make bootstrap` |
| `sql/55_evidence.sql` | The evidence ledger: every answer's SQL, parameters and result hash | done; `make evidence`, runs after `roles` |
| `tests/golden/headline_numbers.sql` | Independent SQL for the headline numbers (verifier-written) | done |
| `scripts/parse.py` | BGL + OpenStack → Parquet (zero lines lost) | done |
| `scripts/md2pdf.py` | Markdown → PDF, for the plan and the write-ups | done |
| `src/exhibit/` | **The MCP server**: persona-aware registry, result envelope, twelve tools (incl. the answer lints), the evidence ledger | done, 101/101 checks |
| `scripts/stage2_mcp_client.py` | Stock-client acceptance check — launches the server over stdio and uses it | done |
| `pyproject.toml` | uv project; `mcp` 2.x (`MCPServer`) + psycopg 3 | done |
| `data/ownership.csv` | **The team-ownership table** (see below) | done |
| `sql/90_queries.sql` | The reference investigations, as the demo runs them | done, `make demo` |
| `docs/worked-investigation.md` | **The written worked investigation**: both questions, every tool call, the executed SQL, the results, the three role answers with recommended actions, scope and filters, observed facts separated from hypotheses | done |
| `tests/golden/` | Independent SQL (written without the views) for the headline, Stage 3, W2 and slide numbers | done, 76/76 and 46/46 rows true; 17/17 slide claims |
| `evals/` | **The evaluation set**: 15 questions, hand-written golden SQL, one score | done, `make eval` → 15/15 |
| `docs/battery.md` · `evals/battery/` | **Adversarial verification**: 29 judge-style questions against the live endpoint, 8 defects found and fixed, question set + results + two transcripts | done, 29/29, 0 crashes |
| `scripts/validate_ground_truth.py` | **Ground truth, outside the agent**: `anomaly_labels.txt` vs the `durations` ranking; BGL label vs text-only signatures | done, `make validate` → 13/13 |
| `sql/70_bench.sql` | The huge-datasets bench: the 1B-row remote OTel file, and an index on a view over Parquet | done, `make bench`; results in `bench/README.md` |
| `docs/validation.md` · `docs/disclosure.md` | What the validation establishes · models, tools, datasets, what was built in the window | done |
| `docs/slides.md` · `docs/slides.pdf` · `docs/VERIFY.md` | The deck, every slide number with its source, and the independent re-derivation of the new slide figures | done |
| `docs/video-script.md` | The recording sheet for the video: what to show, what to say, what you should see | done |
| `docs/followup-questions.md` · `docs/plan.pdf` | Questions we sent the challenge owners · the plan as a PDF | kept for transparency |
| `scripts/probe_capabilities.sh` | The capability probe behind `docs/capabilities.md` (`make probe`) | done |
| `bench/run_ladder.sh` | The bench at 1 s and 10 s slices, each index sized on disk (`make bench-ladder`) | done |
| `.mcp.json` | MCP client config: the local stdio server, the live demo endpoint, the SereneDB docs server | done |
| `docs/process/` | Our working documents: the operating plan, the build reference, the handoff log, the kickoff brief | kept for transparency |
| `LICENSE` | MIT | done |

Nothing in this repo is aspirational: a row marked *done* has been executed on the live corpus,
and the stage numbers refer to `docs/process/PLAN.md` §11.

## Run the agent

```bash
make setup     # uv sync — creates .venv and installs mcp + psycopg
make check     # acceptance: 101 checks against measured numbers, then a stock MCP client
make mcp       # run the server on stdio; point any MCP client at it
```

**Connecting to a SereneDB instance.** The server and the checks read the connection from the
environment (`src/exhibit/db.py`; template in `.env.example`), so pointing them at another instance
is a matter of setting these. The `make` SQL targets take the same instance through `PSQL`.

| Variable | Default | Meaning |
|---|---|---|
| `SERENEDB_HOST` · `SERENEDB_PORT` | `127.0.0.1` · `7890` | where SereneDB listens |
| `SERENEDB_USER` · `SERENEDB_PASSWORD` · `SERENEDB_DB` | `postgres` · *(none)* · `postgres` | the login; each persona then runs under its own role via `SET ROLE` |
| `EXHIBIT_PERSONA` | `engineer` | the persona used when a tool call names none |
| `EXHIBIT_QUERY_TIMEOUT` | `30` | seconds; enforced client-side, because 26.09.1.3 accepts `statement_timeout` but does not enforce it |
| `EXHIBIT_MCP_TRANSPORT` | `stdio` | `streamable-http` serves on `EXHIBIT_MCP_HOST:EXHIBIT_MCP_PORT` + `EXHIBIT_MCP_PATH` (`127.0.0.1:8900/mcp`) |

**Starting the agent workflow.** Any MCP client that can launch a stdio server works. The repo's
own `.mcp.json` registers it for clients that read project config; elsewhere, the usual shape is:

```json
{ "mcpServers": { "exhibit": { "command": "uv", "args": ["run", "--directory", "/path/to/exhibit", "exhibit-mcp"] } } }
```

The server's instructions tell the model the rules (quote the evidence id, ask as the persona whose
question it is, never compute a figure itself, lint before answering). Then ask a question as a role,
for example *"As the team lead: which BGL problem should we staff first?"*. The model picks the
tools; every tool returns the envelope below, and `verify_evidence` re-runs any of them.

### Tool reference: inputs and outputs

Common inputs, accepted by every data tool: `persona` = `engineer` | `lead` | `manager` (default
`engineer`); `limit` (default 20, capped at 200; `trend` caps at 400 buckets); `since` / `until`
(ISO dates or timestamps on the dataset's own clock, 2005–2006 for BGL, 2017 for OpenStack);
`level` and `team` filters where the role's relation carries them. `dataset` is `bgl` or `openstack`.
**Required** inputs are in bold.

| Tool | Inputs | Returns (in `rows`) |
|---|---|---|
| `describe_data` | `dataset`, `persona` | per readable dataset: relation, shape (raw or aggregated), total, time range, whether it can search, the `group_by` options, columns never to sum |
| `search_logs` | **`dataset`**, **`query`**, `mode` = `phrase` (default) \| `term` \| `any` \| `all` (comma-separated terms), `since`, `until`, `level`, `team`, `limit` (default 10) | matching lines newest first: id, ts, node (BGL) or service and instance (OpenStack), level, team, highlighted match, message cut to 300 chars; `total_matches` is the true count. Engineer only |
| `count_events` | **`dataset`**, `group_by` (any column `describe_data` lists: signature, component, level, team, node, problem, …), `query` + `mode` (engineer only), `since`, `until`, `level`, `team` | `bucket`, `n`; `measure` says whether `n` counts rows (raw relation) or sums the view's measure (aggregated relation) |
| `episodes` | **`dataset`**, `gap_minutes` (default 5; a parameter for the engineer only), `coalesce_by` = `failure_domain` (default) \| `signature`, `signature`, `since`, `until`, `level`, `team` | one row per incident: signature, failure domain, lines, distinct nodes, started, ended, span; `total_matches` is the incident count |
| `top_signatures` | **`dataset`**, `by` = `episodes` (default) \| `lines` \| `nodes`, `gap_minutes`, `since`, `until`, `level`, `team` | problems with lines, episodes and blast radius side by side (nodes for BGL, requests affected for OpenStack), ordered by `by` |
| `trend` | **`dataset`**, `bucket` = `hour` \| `day` (default) \| `week`, `days` (counted back from the data's last timestamp), `since`, `until`, `level`, `team` | `bucket`, `n` per bucket; refuses a bucket finer than the role's relation |
| `durations` | `dataset` (default `openstack`), `by` = a lifecycle phase (`spawn_s` default, `build_s`, `image_s`, `boot_s`, `run_s`, …; the manager: `spawn_p50_s`, `spawn_p95_s`, `spawn_max_s`, …), `team` | engineer and lead: instances worst first; manager: the distribution per file group, no instance ids. OpenStack only |
| `ownership` | `dataset`, `team` | the ownership rows (dataset, key_type, key_value, team) and a coverage check against the corpus (unowned keys). Refused for the manager, whose views carry `team` on every row |
| `nearby_events` | **`dataset`**, `id` or `ts` (one anchor), `minutes` (default 15) | the lines within ±`minutes` of the anchor, the busiest signatures in the window, the id range. Engineer only |
| `what_changed` | **`dataset`**, `window_hours` (default 6), `baseline_hours` (default 24), `min_lines` | per signature or problem: rate per hour in the window and in the baseline, `rate_ratio`, `is_new`; anchored to the data's last timestamp |
| `verify_evidence` | **`evidence_id`**, `sample` (default 3) | the stored statement re-run under the stored role and parameters: `match` true/false, rows recorded against rows now, hashes |
| `lint_answer` | **`answer`** (the draft text), `persona`, `deep` (default false: re-run each cited statement and look for the figures in its rows) | verdict `ok` \| `warnings` \| `rejected`, one row per finding; no evidence id, nothing written to the ledger |

**The envelope.** Every data tool returns the same JSON object: `tool`, `dataset`, `persona`,
`role` (the database role it ran under), `refused` (true, with the reason in `notes`, when the role
may not ask this; no SQL runs), `measure` (null = rows counted, else the column summed), `scope` (the
filters applied), `evidence_id`, `total_matches` (the true total), `returned`, `truncated`,
`operator` (`phrase (ts_phrase)`, `term`, `any`, `all`, or plain aggregation), `columns`, `rows`,
`query` (the executed SQL with the parameters bound in) and `notes`. Log text inside `rows` is
untrusted data and is cut to 300 characters.

The server exposes twelve tools, each returning an **envelope** — the rows plus the SQL, the bound
parameters, the operator that produced the counts, the true match total, a truncation flag and a
stable evidence id:

| Tool | Answers |
|---|---|
| `describe_data` | what this role can ask, over what period, grouped how |
| `search_logs` | find evidence — matching lines with highlighted terms, plus the real total |
| `count_events` | how many, bucketed by whatever the role's view exposes |
| `episodes` | **incidents, not lines** — lines coalesced by signature x failure domain at a stated gap |
| `top_signatures` | ranked problems, with lines **and** episodes **and** blast radius side by side |
| `trend` | a number over time, anchored to the data's own clock |
| `durations` | OpenStack lifecycle phases, worst first — the only route to the labelled anomalies |
| `ownership` | the team-ownership table, checked against the corpus rather than trusted |
| `nearby_events` | what else was happening around one line (engineer only) |
| `what_changed` | foreground against baseline, rate-normalised |
| `verify_evidence` | re-runs any stored answer and compares it hash for hash |
| `lint_answer` | checks an answer before it goes out: the manager's vocabulary rule, and every figure cited to evidence that resolves |

Every tool takes a **persona** — and that is not a label. Each persona runs under its own database
role, so scope is enforced by the engine rather than by a prompt:

| Persona | Role | Reads | Can search | The question it asks |
|---|---|---|---|---|
| `engineer` | `exhibit_engineer` | `bgl_ev` / `os_ev` — raw lines | yes, `bgl_idx` / `os_idx` | what is broken, where, and what the log actually says |
| `lead` | `exhibit_lead` | `lead_bgl_daily` / `lead_os_hourly` — per day/hour | **no** — no grant on the base table | which team's work is this, and is it getting better |
| `manager` | `exhibit_manager` | `mgr_bgl_risk` / `mgr_os_risk` / `mgr_rollup_daily` | **no** | what to fix first, and why should I believe it |

```
$ uv run python scripts/stage2_mcp_client.py
connected: exhibit 0.3.0
tools: describe_data, search_logs, count_events, episodes, top_signatures, trend, durations,
       ownership, nearby_events, what_changed, verify_evidence, lint_answer

the same question, asked as the three personas
  engineer  [E-4BDFE1] count_events: 4,747,963 matching rows (showing 2) | engineer@exhibit_engineer
            top: [('compute-platform', 4325112), ('workload-runtime', 228536)]
  lead      [E-3CDBEC] count_events: 4,747,963 sum of lines (showing 2) | lead@exhibit_lead
  manager   [E-EEAF08] count_events: 348,460 sum of alert_lines (showing 2) | manager@exhibit_manager
            top: [('compute-platform', 284391), ('workload-runtime', 63845)]

and the lead asking for log text
  [E-1E4213] search_logs: NOT PERMITTED for lead@exhibit_lead | dataset=bgl, query=ciod
  full-text search is not available to lead: a search on an index relation is privilege-checked
  against the base table, which this role has no grant on.

incidents, not lines
  [E-55EF08] episodes: 19,250 matching rows (showing 1) | engineer@exhibit_engineer, gap_minutes=5
    deepest incident: data TLB error interrupt on R30-M0 — 152,182 lines, 1 node, 6:21:47.98

and the same question at an hour's gap, as the lead (whose relation is pre-grouped)
  [E-0C21D1] episodes: NOT PERMITTED for lead@exhibit_lead | dataset=bgl, gap_minutes=60
  lead reads bgl_incident, where incidents are already grouped at a 5-minute gap, so the gap is
  not a parameter for this role.

re-running the first answer from the evidence ledger
  E-55EF08: match=True (19,250 rows recorded, 19,250 now)
  MATCH — re-running the stored statement returns the same rows

ranked by blast radius instead of volume
  Microloader Assertion on R51-M1: 520 nodes, 1,048 lines, 2 episodes
```

Three totals for one question, each correct for what that role can see: the engineer counts raw
**rows**, the lead **sums** `lines` over its daily rollup, and the manager sums `alert_lines` — alert
lines only, because that is what its view holds. The envelope says which it did.

Note what happens in the last three blocks. The gap in `episodes` is a real parameter for the
engineer and **not** for the lead, who reads a relation where the five-minute grouping is already
done — so instead of quietly returning a different number, the tool refuses and says why. The
answer that *was* given can then be re-run from the ledger and compared: not "trust us", but "run
it yourself". And ranking the same corpus by blast radius instead of volume surfaces a different
problem entirely, which is the finding the whole project is built around.

> [!important] Three rules the server enforces
> Search runs against the **index relation** (`bgl_idx`), never the base table — `@@` against a
> plain table fails even with an index attached to it. Every count states the operator that produced
> it, because `@@`, a non-alpha splitter and `ILIKE` give three different numbers on the same data.
> And a role that may not read something gets `refused: true` with the reason, because the database
> said no — not because a system prompt asked nicely.

## Live demo endpoint

The same server also runs as a public streamable-HTTP endpoint, so a judge — or a teammate —
can connect an MCP client to the running system without cloning anything:

- **URL:** `https://hermes.bushbaby-platy.ts.net:10000/mcp` (streamable HTTP)
- Point any MCP client that speaks HTTP at it — the usual `mcpServers` shape:

  ```json
  { "mcpServers": { "exhibit-demo": { "type": "http", "url": "https://hermes.bushbaby-platy.ts.net:10000/mcp" } } }
  ```

- The endpoint is an MCP tool surface only: read-only queries, and the same engine-enforced
  personas — the `persona` argument still decides which database role runs the query.
- Locally the same mode is `make mcp-http` (`127.0.0.1:8900/mcp`); the mechanism is
  `EXHIBIT_MCP_TRANSPORT=streamable-http uv run exhibit-mcp`. The demo instance runs under
  systemd on the team's box for the duration of the challenge.

## The ownership table

The challenge supplies none, so we invented one and documented it in
`data/ownership.csv`: `dataset, key_type, key_value, team`. Three key types with a
documented precedence — **logger > service > component** — because an OpenStack logger
name is more specific than the novaclient service it belongs to. Keys that match nothing
become `UNOWNED`, which is a real answer and stays visible in every team-level view.

Teams are fictional but coherent: `compute-platform`, `workload-runtime`, `storage-platform`,
`network-fabric`, `site-infrastructure`, `observability`, `cloud-api`, `scheduling`,
`image-service`, `metadata-service`, `platform-services`, `identity`.

Coverage after the join: **100%** of both corpora. BGL's `KERNEL` component alone is
4,324,967 lines, which is itself a demo point — one owning team holds 91% of the corpus.

## Reproducing our results

```bash
make bootstrap smoke   # loads, indexes, and prints the three headline numbers
make demo              # runs the two worked investigations end to end
make eval              # 15 questions, every figure against hand-written golden SQL: 15/15
make validate          # ground truth, outside the agent: 13/13 expectations
make bench             # the 1B-row remote file: a slice indexed in place, bytes and times printed
```

Judges can reproduce every claim from a clean checkout: the derive, the index, the
investigations and the agent are all in this repo, and `make clean-check` runs the whole
sequence in a fresh clone. To reproduce exactly the version that was judged, clone the tag:
`git clone --branch v1.0 https://github.com/Arnie1x/exhibit.git`.

**[`docs/worked-investigation.md`](docs/worked-investigation.md) is the written worked investigation**
the submission asks for: the two questions (W1 over BGL, W2 over OpenStack), every tool call with the
executed SQL, the results, then the answers and recommended actions for the engineer, team lead and
manager — with the data scope, time periods and filters stated, truncation called out, and observed
facts separated from hypotheses. `make demo` prints the same numbers.

## The answer lints

Two rules are enforced in code rather than promised in prose (`src/exhibit/lint.py`, tool
`lint_answer`): **a manager answer may not claim money, downtime, customers, revenue or an SLA**
(quoting a log line is fine, claiming is not), and **every figure must cite evidence that
resolves** — with `deep=true` the cited statement is re-run and the figure has to be supported by
its own result, its aggregates, or the total the envelope reported. An answer that fails is
rejected with one finding per problem; the lint never rewrites the answer, because a lint that
edits is a lint nobody can check. It carries no evidence id of its own: the ledger holds
re-runnable statements, and a lint is an opinion about prose.

## Validation against ground truth

`make validate` scores our analysis against the answer keys that ship with the corpora, from a
script the agent cannot call (`docs/validation.md`):

* **OpenStack.** `anomaly_labels.txt` is read from disk and never loaded; no tool and no table holds
  it. The lead's own `durations` ranking puts the 4 labelled instances at **positions 1–4 of 2,069**
  (by spawn time and by image phase). The two places an agent would look first find nothing: none of
  their 100 lines is above INFO, and API latency is 0.2340 vs 0.2341 s between the files.
* **BGL.** The label column is part of the data, so we do not claim the agent is blind to it.
  Instead: signatures computed from message text alone agree with the label on **99.9998%** of
  4,747,963 lines (as an alert detector, precision 0.999991 and recall 0.999983), against 0.4065
  precision for a FATAL-or-FAILURE filter. Ranking by signature loses nothing the label knew.

## Adversarial verification: 29 judge-style questions

The question a stranger asks is whether the server holds up when someone talks to it like a human.
So we asked it 29 judge-style questions — engineer 8, team lead 5, manager 6, cross-cutting and
adversarial 10 — against the **live public endpoint**, with a real MCP client, a fresh session per
question, and deliberately varied phrasings (vague, terse, informal, wrong-premise, refusal probes,
bad parameters). Every question was then checked against the server's evidence ledger and journal
rather than against the model's prose.

Result: **29/29 answered, zero crashes, zero opaque errors, zero fabricated numbers, zero claims of
cost or downtime** — after the battery had found and we had fixed eight real defects
(PRs #12–#14), including a parameter that arrived in the wrong slot whenever a full-text search was
combined with a filter, and a `verify_evidence` call that crashed on an id that was never issued.
Totals for the final run: 914 tool calls, 166 empty-or-refusal envelopes (all deliberate),
71 minutes of agent time. The per-question method, the defect table, two full transcripts and the
honest accounting of where the harness's own keyword checks fell short are in
[`docs/battery.md`](docs/battery.md); the question set and results are in `evals/battery/`.

## Huge data: the 1-billion-row remote file

`make bench` indexes a slice of the organisers' 1B-row OTel Parquet file (41 GB on S3) in place,
through an inverted index on a view, and prints how much it read (`bench/README.md`). The whole
file's shape comes from its footer in about 2 s. Ten seconds of data, 5,275,597 rows, are pruned to
10 of 1,624 row groups and indexed in 60 s; a phrase search on that index then takes 13 ms and never
touches S3. One setting decides whether this works on 26.09.1.3: **`SET enable_external_file_cache
= false`**. With the default, reads are not pruned and big ones crash the server, which is recorded
with its reproduction in `docs/capabilities.md` §11 rather than left out.

**Amount queried, times and cost** (`bench/README.md`, machine: 16 vCPU, 7.6 GB Docker VM): the
file is 1,000,000,000 rows and 40,991,166,725 bytes; its shape comes from the 4.8 MB footer in
1.4–3.3 s; the indexed slice is 5,275,597 rows from 10 of 1,624 row groups, with bytes read and cold
times per column in the bench table. Cost: the file is read with anonymous HTTPS GETs from a public
S3 bucket, nothing is downloaded to disk, and no storage, egress or query fee was billed to us — the
only cost is the machine the index is built on.

## Disclosure

Per the challenge rules, the tools, models and datasets used are listed in
`docs/disclosure.md`, together with what was built during the build window and what
existed before it.

## Limitations

Stated deliberately, because the brief rewards separating measured facts from hypotheses:
BGL's label column is incomplete (84,253 fault lines carry the `-` "normal" label); our
`template_id` is `UNKNOWN` because no template IDs are supplied; and the OpenStack
anomalies are only visible through lifecycle durations, not through log levels. The ownership
table is our construction, not ground truth. BGL's label is visible to the agent, so its validation
checks agreement rather than blindness. On SereneDB 26.09.1.3 the remote index needs the external
file cache off, and on the 16-vCPU machine we benchmarked on it crashes the server above about ten seconds of the OTel file
(`bench/README.md`). No answer states a cost, downtime or customer figure: the logs cannot support
one, and the manager lint rejects them.

## Licence

MIT. Dataset: Loghub (Zenodo 8196385), used under its own terms.
