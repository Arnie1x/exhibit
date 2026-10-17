# Slides: every number and where it comes from

The deck (13 slides, 16:9, speaker notes on each) lives as a Claude artifact; export it to PDF or
PPTX for submission. This page is its provenance: each figure on a slide, and the command that
prints it. The rule from the team plan §12 holds: a number with no command does not go on stage.
Checked 17 Oct: all 17 corpus claims re-derived by `sql-verifier` with fresh SQL on the raw Parquet, every one a match (`PROGRESS.md`, item 8).

| # | Slide | Figures | Printed by |
| --- | --- | --- | --- |
| 1 | Exhibit: SQL computes, the LLM explains | none | — |
| 2 | Same logs, three decisions | none (role playbooks) | PLAN.md §7, `sql/50_roles.sql` |
| 3 | Lines are not incidents | 152,183 alert lines, 1 node, 2005-06-11 17:17 → 23:39 (6h22m), 44% of alert lines; 49,154 lines on 22,529 nodes (2005-06-14); 348,460 → 19,250 (5 min, signature × midplane) → 1,377 (signature) | `make smoke` §2, §4b; `tests/golden/headline_numbers.sql` |
| 4 | One corpus, three rankings | DTLB 152,734 lines, 117 incidents, 99.64% one node; Lustre 3,667 and ciod `… CioStream socket to {n}.{n}.{n}.{n}:{n}, Link has been severed` 3,638 incidents, at most 8 nodes in one (two other ciod signatures share the prefix: 588 and 443); `rts panic! - stopping execution` 3,394 nodes on 124 days; DTLB 12th on the combined measure | `make demo` W1 E1, L2, M2 |
| 5 | SQL computes, the LLM explains | 12 tools | `src/exhibit/server.py` (`make check` lists them) |
| 6 | Roles are enforced by the database | 4,747,963 rows (engineer); 4,747,963 summed lines (lead); 348,460 alert lines (manager) | `make check`, `scripts/stage2_mcp_client.py` |
| 7 | W1, the lead | compute-platform 91.1% of lines, 81.6% of alert lines, 51.7% of incidents; workload-runtime 48.0%; the same ciod signature: 3,638 incidents, all in the last 9 weeks (in fact the last 8), slope +14.8 a week; Lustre 3,667 in 3 weeks, none in the last 9 | `make demo` W1 L1, L3, L4 |
| 8 | W2, OpenStack | 188 ERROR + CRITICAL lines; 184 = 8 tracebacks (InvalidDiskInfo), 8 incidents; 4 token-validation lines incl. the only 2 CRITICAL, 2 incidents; 184 ERROR → platform-services; 3,059 warnings, 3 incidents → image-service | `make demo` W2 E2, L3, M1; `make smoke` §6; `tests/golden/w2_numbers.sql` |
| 9 | Every number travels with its query | `E-55EF08`: total 19,250, returned 1, DTLB on R30-M0, 152,182 lines, 1 node, 6:21:47.98; MATCH; `make check` 101/101; `make eval` 15/15, 19 figures, 6 refusals | `episodes(bgl, engineer, gap_minutes=5)` + `verify_evidence`; `make check`; `make eval` |
| 10 | Scored against answer keys | 4 of 4 at positions 1–4 of 2,069; chance 1 in 761,325,852,001; 0 of 100 lines above INFO; latency 0.2340 vs 0.2341 s; 99.9998% agreement over 4,747,963 lines; precision 0.999991, recall 0.999983; FATAL/FAILURE precision 0.4065 | `make validate`; `docs/validation.md` |
| 11 | A billion rows, searched where they sit | 1,000,000,000 rows, 41 GB, 1,624 row groups, footer in about 2 s; 5,275,597 rows from 10 s, 10 row groups, 60 s, 136 MB; 13 ms, 290,473 hits; 8.7 MiB of a 297 MB column; 152,734 and 350,567; cache off; 30 s and 60 s crash | `make bench`, `make bench-ladder`; `bench/README.md` |
| 12 | What we do not claim | 84,253 ASSERT lines labelled normal; 23 ownership rows, 100% coverage; 42 categories and 6 levels (brief: 12 and 5) | `docs/data-notes.md`; `make smoke`; `ownership` tool |
| 13 | Run it yourself | about 20 s bootstrap | `make bootstrap` (17.8 s on 16 vCPU) |

Two figures depend on the machine and are stated with it: bench times (16 vCPU, about 6 MiB/s to
S3) and the bootstrap time. Everything else is a property of the corpus and reproduces exactly.
