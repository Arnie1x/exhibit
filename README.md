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
| `tests/golden/headline_numbers.sql` | Independent SQL for the headline numbers (verifier-written) | done |
| `scripts/parse.py` | BGL + OpenStack → Parquet (zero lines lost) | done |
| `scripts/md2pdf.py` | Markdown → PDF, for the plan and the write-ups | done |
| `data/ownership.csv` | **The team-ownership table** (see below) | done |
| `sql/90_queries.sql` | The reference investigations, as the demo runs them | Stage 3 |
| `evals/` | The evaluation set: questions + golden SQL | Stage 5 |

Nothing in this repo is aspirational: a row marked *done* has been executed on the live corpus,
and the stage numbers refer to `PLAN.md` §11.

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
