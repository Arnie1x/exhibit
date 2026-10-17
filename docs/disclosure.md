# Disclosure

Required by the challenge rules ("disclose the models, tools and datasets you used"), and useful
regardless: everything below is what actually produced this repo, including the parts that are not
a model's work.

## Datasets

| Dataset | Source | Licence / terms | What we used it for |
|---|---|---|---|
| **BGL** (Blue Gene/L) | Loghub, Zenodo record 8196385 | used under Loghub's own terms | the primary corpus: 4,747,963 lines, 2005-06-03 → 2006-01-04 |
| **OpenStack** | Loghub, Zenodo record 8196385 | used under Loghub's own terms | the second corpus: 207,812 lines, 2017-05-14 → 2017-05-17 |
| `anomaly_labels.txt` (OpenStack) | Loghub, same record | — | ground truth for the OpenStack anomalies. **The agent never sees it**: it is used only by `scripts/validate_ground_truth.py`, which checks what our analysis recovered rather than being an input to it |

Both corpora are used as supplied; we do not redistribute them in this repository (`make fetch`
downloads them). Nothing here is a real customer's data: Loghub's corpora are published research
sets.

## Software

| Component | Version | Role |
|---|---|---|
| **SereneDB** | 26.09.1.3 (the arm64-clean tag; 26.10.x is amd64-only) | the engine: derivation, indexes, the analytic views, and every number in this repo |
| Python | 3.12 (`uv` 0.13.1) | the MCP server, the tools, the checks |
| `mcp` | 2.x (`MCPServer`) + psycopg 3 | the server surface and the driver |

## AI assistants

Both team members used AI coding assistants during the build window. The challenge rules permit
this and require us to say so, so here is exactly what each was used for:

| Assistant | Used by | For |
|---|---|---|
| **Anthropic Claude** (Claude models, in an AI coding assistant) | Person A | the SQL lane: the derived tables, the indexes, the role views, the investigations in `sql/90_queries.sql`. Also connected to the SereneDB documentation MCP server (a challenge prerequisite) |
| **Hermes Agent** (Nous Research, `deepseek-v4.1-flash` via opencode-go) | Person B | the tool lane: the persona registry, the result envelope, the analysis tools, the evidence ledger, the answer lints, the eval harness, and this repository's documentation |

What that means in practice, and what it does not:

* every number in this repository is **computed by SereneDB**, never by a model. The assistants wrote
  SQL and Python; the figures come from the database and are pinned by `make check` and `make eval`;
* the assistants' output was reviewed and verified by the other team member: Person A's figures were
  recomputed independently (76 of 76 checks, without using his views) and Person B's tools were run
  against Person A's numbers through the real MCP surface;
* the agents did **not** write the analysis claims: the findings in `PLAN.md` §9 and the demo come
  from measured queries, and the two claims that did not survive measurement are recorded in
  `docs/data-notes.md` and the commit history rather than quietly dropped;
* no model runs inside the submitted system. The MCP server is deterministic Python over SereneDB;
  an LLM client is what consumes it. Nothing in the answer path needs a model to be present.

## What was built during the build window

Everything in `src/`, `sql/`, `evals/`, `scripts/` and `docs/` was written during the hackathon
window (16–21 October 2026). Nothing was carried over from before it. The corpora are pre-existing
published datasets, as the track intends. The team-ownership table (`data/ownership.csv`) is ours —
the brief does not supply one — and it is documented as our construction, not as ground truth.

## Prerequisites the track asked for

* SereneDB starred on GitHub (both team members).
* The SereneDB documentation MCP server connected to a coding assistant (Person A's assistant).

## A note on the numbers people ask about

Two figures circulated during the build that we could not reproduce, and we say so rather than
repeat them: the brief's "twelve labelled alert categories" (BGL's category column has 42 distinct
values, 41 plus `-`) and its "five severity levels" (we measure six, no `Kill` in the derived set).
Both were raised with the challenge owners at the Q&A. The brief's "44% of all alert lines" figure
was ours to correct, and `PLAN.md` now carries the measured version.
