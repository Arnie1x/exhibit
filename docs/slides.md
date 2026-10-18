# Slides: every number and where it comes from

The deck is the Canva presentation "Exhibit: SQL computes, the LLM explains" (17 slides, 16:9, the
video narration in each slide's speaker notes), rebuilt on 18 Oct from a Canva template and
exported to `docs/slides.pdf` for the submission. It replaces the 13-slide deck of 17 Oct and adds
what landed since: the MCP server's three connection paths and the live demo endpoint, the twelve
tools and their limits, a weekly chart for the lead and a spawn-time chart for W2, and the Q&A
ruling that the data, not the brief, is authoritative.

This page is its provenance: each figure on a slide, and the command that prints it. The rule from
the team plan §12 holds: a number with no command does not go on stage. Checked 18 Oct on
SereneDB 26.09.1.3 after a fresh `make bootstrap`: `make smoke`, `make demo`, `make check`
(101/101), the stock-client script, `make eval` (15/15) and `make validate` (13/13) print every
corpus figure below, and they still do on `dc59a95` (main with the tools fix of 18 Oct). The live
endpoint was called from a second machine the same day (slide 7). The figures new since 17 Oct
(the slide 10 bars, DTLB's nodes and days, 18.1 lines per incident, the spawn median and fifth
place) were re-derived by `sql-verifier` with fresh SQL on `bgl_ev` and `os_ev`, without the
views: 24 of 24 match (`docs/VERIFY.md`).

Canva's generator wrote placeholder numbers and two charts of invented data into the template; every
text box was rewritten by hand and both charts were replaced with bars drawn from the SQL output
below. No figure on a slide comes from the generator.

| # | Slide | Figures | Printed by |
| --- | --- | --- | --- |
| 1 | Exhibit | terminal card: `connected: exhibit 0.3.0`, 12 tools, `E-55EF08` 19,250 incidents, MATCH | `scripts/stage2_mcp_client.py` (`make check`) |
| 2 | One question, three readers | none (role playbooks) | PLAN.md §7, `sql/50_roles.sql` |
| 3 | Lines are not incidents | 152,183 alert lines from 1 node in 6h22m (2005-06-11), 44% of alert lines; 49,154 lines across 22,529 nodes (2005-06-14); 348,460 → 19,250 (5-min gap, signature × midplane) → 1,377 (signature) | `make smoke` §2, §4, §4b; `tests/golden/headline_numbers.sql` |
| 4 | One corpus, three rankings | by lines: DTLB 152,734 lines, 117 incidents, 99.64% from one node; by incidents: Lustre 3,667, ciod socket 3,638, at most 8 nodes in one; by blast radius + persistence: rts panic 3,394 nodes, 124 active days, DTLB 12th | `make demo` W1 E1, L2, M2 |
| 5 | How Exhibit works | 12 tools; SereneDB 26.09.1.3 | `src/exhibit/server.py` (`make check` lists them) |
| 6 | Twelve tools, one envelope | the 12 tool names in four groups; envelope fields; at most 200 rows, 400 buckets, 30-second client-side deadline | `src/exhibit/server.py`, `envelope.py`, `analytics.py` (`MAX_ROWS`, `MAX_BUCKETS`, `TEXT_CHARS`), `db.py` (`TIMEOUT_S`) |
| 7 | Three ways to connect, one of them live | `.mcp.json` (`uv run exhibit-mcp`); `make mcp-http` on `127.0.0.1:8900/mcp`; `https://hermes.bushbaby-platy.ts.net:10000/mcp`; tested 18 Oct: 12 tools, `E-55EF08` identical to a local run, `verify_evidence` MATCH | `.mcp.json`, `Makefile`, README "Live demo endpoint"; the call: an MCP client over streamable HTTP (`initialize`, `list_tools`, `episodes`, `verify_evidence`), 5 of 6 runs clean, 1 `SSE stream ended without a response` |
| 8 | Roles enforced by the database | 4,747,963 rows (engineer); 4,747,963 lines summed from a daily rollup (lead); 348,460 alert lines (manager); lead `search_logs(bgl, "ciod")` NOT PERMITTED | `make check` (stock-client script, "the same question, asked as the three personas") |
| 9 | W1 engineer: one machine, not the fleet | phrase search 152,734 lines; 117 incidents at 5 min; 99.64% of lines on one node; deepest incident R30-M0, 152,182 lines, 1 node, 6:21:47.98 (`E-55EF08`); 132 / 117 / 57 incidents at 1 / 5 / 60 min | `make check`; `make demo` W1 E1, E2, E4 |
| 10 | W1 team lead: one stopped, one is still active | compute-platform 91.1% of lines, 81.6% of alert lines, 51.7% of incidents; workload-runtime 48.0% of incidents; weekly bars: Lustre 1,872 · 1,244 · 551 (weeks of 29 Aug, 5 Sep, 12 Sep 2005), total 3,667; ciod 213 · 1,110 · 789 · 136 · 900 · 186 · 286 · 18 (weeks of 14 Nov 2005 to 2 Jan 2006), total 3,638, all in the last 9 weeks | `make demo` W1 L1, L3, L4, L4b |
| 11 | W1 manager: a slow burn outranks a fire | 348,460 alert lines → 19,250 incidents, 18.1 lines each; risk 1: rts panic, KERNEL, compute-platform, 3,394 nodes, 124 active days; DTLB 12th, 1st by lines (152,734), 541 nodes, 11 days, 99.64% on one node; "Not established by the logs: cost, downtime, impact on jobs or users, root cause" | `make demo` W1 M1, M2, end of the manager section |
| 12 | W2 OpenStack: only lifecycle finds the slow ones | 188 ERROR + CRITICAL lines = 8 tracebacks of one image-cache bug + 2 token incidents; API latency 0.2340 vs 0.2341 s; spawn bars: a445709b 50.72, 544fd51c 41.81, 1643649d 31.27, ae651dff 29.46, d7d68893 26.69 s, median 19.74 s; the 4 labelled instances at 1 to 4 of 2,069 | `make smoke` §6, §6b; `make demo` W2 E1, E2, L1, L2, M1; `make validate` §1 |
| 13 | Every number travels with its query | the `E-55EF08` envelope (`episodes(bgl, engineer, gap_minutes=5)`: total 19,250, returned 1, truncated, DTLB on R30-M0, 152,182 lines, 1 node, 6:21:47.98); `verify_evidence` MATCH, 19,250 rows recorded and now; `make check` 101/101; `make eval` 15/15, 19/19 figures, 6 refusals | `make check` (stock-client script); `make eval` |
| 14 | Scored against answer keys, outside the agent | 4 labelled at 1 to 4 of 2,069; chance 1 in 761,325,852,001; 99.9998% agreement over 4,747,963 lines; precision 0.999991 (signatures) vs 0.4065 (FATAL/FAILURE); 0 of 100 lines above INFO; latency 0.2340 vs 0.2341 s; 13/13 | `make validate`; `docs/validation.md` |
| 15 | A billion rows, searched where they sit | 1,000,000,000 rows, 41 GB on S3, 1,624 row groups, footer in about 2 s; 10-second slice: 5,275,597 rows from 10 row groups, built in 60 s, 136 MB on disk; phrase + facet 13 ms, 290,473 hits; 30 s and 60 s slices crash; 16 vCPU, about 6 MiB/s | `make bench`, `make bench-ladder`; `bench/README.md` |
| 16 | What we do not claim | 23 ownership rows, fictional teams, 100% coverage; brief 12 categories and 5 levels, data 42 and 6, the organisers' ruling; 84,253 ASSERT lines labelled normal | `ownership` tool; `make smoke`; PLAN.md §13; `docs/data-notes.md` |
| 17 | Run it yourself | about 20 s bootstrap | `make bootstrap` (15.8 s on the Windows box, 18 Oct) |

Two figures depend on the machine and are stated with it: bench times (16 vCPU, about 6 MiB/s to
S3) and the bootstrap time. Everything else is a property of the corpus and reproduces exactly.

The slide 10 bars are drawn to scale (1,872 incidents = full height) and the slide 12 bars to scale
(50.72 s = full width); the numbers printed beside them are the SQL output, not readings off the bars.
