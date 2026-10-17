# SereneDB capability matrix — measured on 26.09.1.3

Probed against the live instance on 17 Oct 2026, arm64, 2 vCPU / 12 GB, database `postgres`.
Every row is a statement that was executed; PASS/FAIL is what the engine returned, not what the
docs say. This is the Stage 0 `docs/capabilities.md` artefact, filled in ahead of time.

Why the version matters: `26.10.x` releases are **amd64-only**, so an ARM development box is pinned to
**26.09.1.3**. Any docs statement about a feature added after 26.09 may not hold here.

## 1. The architecture question: what can `@@` run against?

This is the one that decides our schema, so it was tested four ways.

| Setup | `@@` works? | Evidence |
|---|---|---|
| Plain table, **no** inverted index | **FAIL** | `TSQUERY expression evaluated outside an \`@@\` match against an inverted-indexed column.` |
| Plain table, **with** a `USING inverted` index attached | **FAIL** | same error — the index does not make the table addressable |
| The **index relation itself**, named in `FROM` | **PASS** | `SELECT count(*) FROM probe_plain_idx WHERE content @@ 'parity'` → 1 |
| A table created `WITH (storage = 'search')` | **PASS** | `SELECT count(*) FROM bgl WHERE content @@ 'parity'` → 121,498 |

**Conclusion, and it confirms the plan's claim.** `@@` must run against an inverted-indexed relation:
either the index relation by name (`*_idx`), or a search table. Adding an index to a plain derived
table does **not** make that table queryable — which means the plan's `bgl_ev` + `bgl_idx` split is
correct as written, and any tool written against `bgl_ev` directly will fail with the error above.

Two workable patterns, pick one before writing any tool:

- **A — search tables.** `CREATE TABLE bgl_ev WITH (storage='search') …` + index. `@@` works on the
  table name. Fewer moving parts; the table *is* the indexed relation.
- **B — plain derived tables + separate index relation.** Exactly as the plan describes; every search
  targets `bgl_idx`, not `bgl_ev`. Needed if the supplied loader hands us plain tables.

## 2. Confirmed working (the plan can rely on these)

| Capability | Probe result |
|---|---|
| `ts_phrase`, `ts_any([…])`, `ts_all([…])`, `ts_levenshtein`, `ts_starts_with`, `ts_regexp` | PASS — 152,734 / 274,012 / 63,493 / 121,498 / 208,851 / 202,310 |
| `to_tsquery` (Lucene), `websearch_to_tsquery` | PASS — both 152,734 |
| `ts_dict_agg`, `ts_dict_count` (facets, significant terms) | PASS |
| `ts_highlight(content, ts_offsets(content))` | PASS — returns `<b>parity</b>` markup |
| `BM25(<index>.tableoid)` | PASS — 1.92 |
| `percentile_cont(0.95) WITHIN GROUP (ORDER BY col)` | PASS — 0.3818 |
| `quantile_cont(col, 0.95)` | PASS — 0.3818 (agrees with the above) |
| `date_bin`, `date_trunc`, `generate_series`, `regr_slope` | PASS |
| `GROUPING SETS`, `GROUP BY ALL` | PASS |
| `LAG`, `SUM() OVER (… ROWS UNBOUNDED PRECEDING)` | PASS — the episode algorithm runs |
| `EXTRACT(epoch FROM ts)`, `ts + INTERVAL '5 minutes'` | PASS |
| Array literals `[1,2,3]` and `ARRAY[1,2,3]` | PASS — both |
| `sdb_indexes()`, `sdb_metrics`, `sdb_functions()` | PASS |
| `EXPLAIN`, `EXPLAIN ANALYZE` | PASS |
| `regexp_extract` returns `''` on no match | PASS — `[]` proves empty, not NULL |
| `strptime('%Y-%m-%d-%H.%M.%S.%f')` | PASS |
| `CREATE ROLE … LOGIN PASSWORD` | PASS |
| `DELETE`/`DROP` cleanup on the probe objects | PASS |

## 3. Corrected: three claims that do not hold on 26.09.1.3

| Claim | Measured | What to do |
|---|---|---|
| `CREATE TEXT SEARCH DICTIONARY log_text AS split_text(case := 'lower') WITH (frequency, position, offset)` | **syntax error at or near "AS"** | Use the form that works: `CREATE TEXT SEARCH DICTIONARY en (template='split_by_non_alpha', case='lower', frequency=true, norm=true, position=true)` |
| `sdb_metrics(num_docs, index_size)` gives index build size | **No such rows.** `sdb_metrics` columns are `(metric, value, description, relation_id)` and its rows are connection/refresh/compaction counters. `sdb_indexes()` columns are `(table_name, index_name, schema_name, comment, is_unique)` — no size or row count. `pg_class` reports `relpages = 0`, `reltuples = -1` for these indexes. | Measure index cost by wall-clock build time and the data directory on disk. Do not promise size numbers we cannot produce. |
| Partial inverted index (`… USING inverted (…) WHERE ts >= …`) restricts the index | **No measurable effect.** Naming the partial index returns the full count (121,498) while the same window predicate against the table returns 0; `EXPLAIN` chooses `Index: bgl` and applies `ts` as a **Column Filter**, not an index restriction; timing is unchanged (4.19 ms vs 3.99 ms). | Keep workspace indexes **probe-gated**, not a 2-hour commitment. Note also the plan's own honest caveat: when a full index exists, a workspace index adds little — the only place it could pay is the remote lake, where there is no full index. |

## 4. Corrected: two smaller items

- **`VARCHAR(n)` is accepted** — `CREATE TABLE probe_vc (a VARCHAR(10))` succeeded, and inserting 20
  characters stored all 20 (`length(a)` = 20). The rule "never `VARCHAR(n)`" is still right, but for the
  correct reason: **it does not enforce**. Nobody should write validation that assumes a length limit.
- **`BM25()` with no arguments does not exist** on this version; `BM25(<index>.tableoid)` does. The
  plan's cheat sheet uses the `tableoid` form and is correct; a bare `BM25()` is not available.
- **`ts_offsets`/`ts_highlight` require an `@@` match in the same sub-query** — that is what the error
  message says, and it makes the plan's `FROM bgl_idx WHERE content @@ …` form correct.
- Confirmed absent, as the plan says: `to_timestamp(text)` (epoch only), `to_char`, `to_date`.

## 5. Bonus track reality check

| Track | Status after probing |
|---|---|
| Workspace indexes (9a) | **At risk.** Both mechanisms it leans on (partial-index restriction, `sdb_metrics` size) do not behave as documented here. Probe-gate it; expect to report a negative result. |
| Role-scoped access (9b) | **Sound.** `CREATE ROLE … LOGIN PASSWORD`, `GRANT`, column grants and `SET ROLE` all work; a restricted role reading a column it lacks gets `permission denied`. Already verified end to end. |
| Huge datasets (9c) | **Sound.** The engine reads the remote Parquet over HTTPS directly — a `count(*)` over `part_000.parquet` (1B rows) returned in 0.8 s without downloading. Row-group pruning via a `ts` predicate is the honest story; partial indexing is not. |
| Eval harness (9d) | **Sound and cheap.** Golden SQL + tool-selection scoring needs nothing exotic. |
