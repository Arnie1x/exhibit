# Logging off Early — role-aware log intelligence on SereneDB

**National AI Hackathon 2026 · SchubKI · Track 04 — "Making Sense of Logs"**

Two students, 48 hours, one question: *can a database plus an LLM answer the same question
three different ways — for the engineer who fixes it, the lead who has to staff it, and the
manager who has to justify the decision?*

We take BGL and OpenStack logs, index them in SereneDB, and expose them to an LLM agent
through an MCP server whose every answer is computed by SQL and cited back to the exact
query that produced it.

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
49,651 lines, is 7,036 separate episodes per midplane.

Both rankings are in the demo, side by side. That is what "making sense of logs" means.

## Quickstart

```bash
# 1. SereneDB (arm64: 26.09.1.3 is the newest multi-arch tag; 26.10.x is amd64-only)
docker run -d --name serenedb -p 127.0.0.1:7890:7890 \
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

`psql -h 127.0.0.1 -p 7890 -U postgres` — no credentials by default. The server reads files
from **its own** filesystem, hence the `-v "$PWD/data":/data` mount; remote HTTP/S3 Parquet
needs no mount.

## Repository map

| Path | What it is | Status |
|---|---|---|
| `PLAN.md` | The full build plan: stages, gates, allocation, Q&A prep — **§16 is the rule list for coding agents** | done |
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
| `src/exhibit/` | **The MCP server**: persona-aware registry, result envelope, eleven tools, the evidence ledger | done, 80/80 checks |
| `scripts/stage2_mcp_client.py` | Stock-client acceptance check — launches the server over stdio and uses it | done |
| `pyproject.toml` | uv project; `mcp` 2.x (`MCPServer`) + psycopg 3 | done |
| `data/ownership.csv` | **The team-ownership table** (see below) | done |
| `sql/90_queries.sql` | The reference investigations, as the demo runs them | Stage 3 |
| `evals/` | The evaluation set: questions + golden SQL | Stage 5 |

Nothing in this repo is aspirational: a row marked *done* has been executed on the live corpus,
and the stage numbers refer to `PLAN.md` §11.

## Run the agent

```bash
make setup     # uv sync — creates .venv and installs mcp + psycopg
make check     # acceptance: 80 checks against measured numbers, then a stock MCP client
make mcp       # run the server on stdio; point any MCP client at it
```

The server exposes eleven tools, each returning an **envelope** — the rows plus the SQL, the bound
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
       ownership, nearby_events, what_changed, verify_evidence

the same question, asked as the three personas
  engineer  [E-88FE03] count_events: 4,747,963 matching rows (showing 2) | engineer@exhibit_engineer
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
make eval              # scores the agent's answers against golden SQL
```

Judges can reproduce every claim from a clean checkout: the derive, the index, the
investigations and the agent are all in this repo, and `make clean-check` runs the whole
sequence in a fresh clone.

## Disclosure

Per the challenge rules, the tools, models and datasets used are listed in
`docs/disclosure.md`, together with what was built during the build window and what
existed before it.

## Limitations

Stated deliberately, because the brief rewards separating measured facts from hypotheses:
BGL's label column is incomplete (84,253 fault lines carry the `-` "normal" label); our
`template_id` is `UNKNOWN` because no template IDs are supplied; and the OpenStack
anomalies are only visible through lifecycle durations, not through log levels.

## Licence

MIT. Dataset: Loghub (Zenodo 8196385), used under its own terms.
