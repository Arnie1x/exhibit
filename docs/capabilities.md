# SereneDB capability matrix — measured on 26.09.1.3

Probed against the live instance, arm64, 2 vCPU / 12 GB, database `postgres`. Every row is a
statement that was executed; PASS/FAIL is what the engine returned, not what the docs say.
Rebuild it with `make probe`; if a row disagrees, the measurement wins and this file changes.

Why the version matters: `26.10.x` releases are **amd64-only**, so an ARM box is pinned to
**26.09.1.3**. Any docs statement about a feature added after 26.09 may not hold here.

## 1. The architecture question: what can `@@` run against?

This decides the schema, so it was tested four ways.

| Setup | `@@` works? | Evidence |
|---|---|---|
| Plain table, **no** inverted index | **FAIL** | `TSQUERY expression evaluated outside an @@ match against an inverted-indexed column.` |
| Plain table, **with** a `USING inverted` index attached | **FAIL** | same error — the index does not make the table addressable |
| The **index relation itself**, named in `FROM` | **PASS** | `SELECT count(*) FROM probe_idx WHERE content @@ 'parity'` → 1 |
| A table created `WITH (storage = 'search')` | **PASS** | `SELECT count(*) FROM probe_search WHERE content @@ 'parity'` → 121,498 |

**Conclusion.** `@@` must run against an inverted-indexed relation: either the index relation by
name (`*_idx`), or a search table. Adding an index to a plain derived table does **not** make that
table queryable — so the `bgl_ev` + `bgl_idx` split is correct as written, and any query written
against `bgl_ev` directly fails with the error above.

The vendor's own docs, returned by `sdb_docs.search`, agree:

> "An inverted index behaves as a queryable relation: full-text, verbatim, range and geospatial
> predicates are issued by **selecting from the index by name**, with the `@@` match operator on the
> indexed column." — `sql/indexes/inverted/index.md`

Two workable patterns; we use **B**:

- **A — search tables.** `CREATE TABLE t WITH (storage = 'search')` + index; `@@` works on the table
  name. Fewer moving parts; the table *is* the indexed relation.
- **B — plain derived tables + separate index relation.** Aggregation on `bgl_ev` / `os_ev`, every
  full-text predicate on `bgl_idx` / `os_idx`.

## 2. Confirmed working

| Capability | Probe result |
|---|---|
| `sdb_docs.search(query VARCHAR, max_hits INTEGER)` | **The docs are searchable from SQL, offline** → `path, title, breadcrumb, snippet, score`. The one-argument form raises `Macro "search"() does not support the supplied arguments` |
| Built-in `docs` table + `docs_fts` index | listed by `sdb_indexes()` |
| Inverted index over a **view** | **PASS** — the zero-ETL path; only the index is stored locally |
| `REINDEX INDEX <name>` on a view-backed index | PASS — the index is a snapshot; refresh after the source moves |
| `read_parquet` over HTTPS, `read_csv` + `DESCRIBE` inference | PASS — a 1-minute slice of a remote 1B-row Parquet returned in **0.8 s** |
| `ts_phrase`, `ts_any([…])`, `ts_all([…])`, `ts_levenshtein`, `ts_starts_with`, `ts_regexp` | PASS — 152,734 / 274,012 / 63,493 / 121,498 / 208,851 / 202,310 |
| `to_tsquery` (Lucene), `websearch_to_tsquery` | PASS — both 152,734 |
| `ts_dict_agg`, `ts_dict_count` (facets, significant terms) | PASS |
| `ts_highlight(content, ts_offsets(content))` | PASS — returns `<b>…</b>` markup, **but only with an `@@` in the same sub-query** |
| `BM25(<index>.tableoid)` | PASS — 1.92 |
| `percentile_cont(0.95) WITHIN GROUP (ORDER BY col)`, `quantile_cont` | PASS — both 0.3818 |
| `date_bin`, `date_trunc`, `generate_series`, `regr_slope`, `GROUPING SETS`, `GROUP BY ALL` | PASS |
| `LAG`, `SUM() OVER (… ROWS UNBOUNDED PRECEDING)` | PASS — the episode algorithm runs |
| `EXTRACT(epoch FROM ts)`, `ts + INTERVAL '5 minutes'` | PASS |
| Array literals `[1,2,3]` and `ARRAY[1,2,3]` | PASS — both |
| `sdb_indexes()`, `sdb_metrics`, `sdb_functions()`, `EXPLAIN`, `EXPLAIN ANALYZE` | PASS |
| `regexp_extract` returns `''` on no match | PASS — wrap in `NULLIF(x, '')` |
| `strptime`, `CREATE ROLE … LOGIN PASSWORD`, `GRANT`, `SET ROLE` | PASS |

## 3. Corrected: claims that do not hold on 26.09.1.3

| Claim | Measured | What to do |
|---|---|---|
| `CREATE TEXT SEARCH DICTIONARY log_text AS split_text(case := 'lower') WITH (frequency, position, offset)` | **syntax error at or near "AS"** | The documented parenthesised form: `CREATE TEXT SEARCH DICTIONARY log_text (template = 'text', locale = 'en_US.UTF-8', case = 'lower', stemming = false, accent = false, frequency = true, position = true)` |
| `sdb_metrics(num_docs, index_size)` gives index build size | **No such rows.** `sdb_metrics` columns are `(metric, value, description, relation_id)` and its rows are connection/refresh/compaction counters. `sdb_indexes()` has no size or row count. `pg_class` reports `relpages = 0`, `reltuples = -1` for these indexes. | Measure cost by wall-clock build time and the data directory. Never promise size numbers we cannot produce |
| Partial inverted index (`… USING inverted (…) WHERE ts >= …`) restricts the index | **No measurable effect.** Naming it returns the full count (121,498) where the same window predicate against the table returns 0; `EXPLAIN` chooses the full index and applies `ts` as a **Column Filter**; timing identical (4.19 ms vs 3.99 ms). | Keep workspace indexes **probe-gated**, not a 2-hour commitment |
| `PREPARE name(VARCHAR) AS … $1` in psql | `TypeList for prepared statement has not been implemented` | A **psql** limitation only — psycopg's binding works (§6). Do not conclude parameters are broken from it |
| `CREATE FUNCTION … LANGUAGE sql SECURITY DEFINER` enforces owner privileges | **Not honoured** — the definer function still failed with `permission denied for table bgl_ev` | Parameterised search is a **view + an outer predicate**, never a definer function |

## 4. Corrected: smaller items

- **`VARCHAR(n)` is accepted** — `CREATE TABLE probe_vc (a VARCHAR(10))` succeeded, and 20 characters
  stored all 20 (`length(a)` = 20). "Never `VARCHAR(n)`" is still right, but for the correct reason:
  **it does not enforce.** Nobody should write validation that assumes a length limit.
- **`BM25()` with no arguments does not exist**; `BM25(<index>.tableoid)` does.
- **`ts_offsets` / `ts_highlight` require an `@@` in the same sub-query** — that is what the error says.
- Confirmed absent: `to_timestamp(text)` (epoch only), `to_char`, `to_date`.
- `ts_any` / `ts_all` with a **bound parameter** need a cast: `ts_any(%s::TSQUERY[])` → 382,098. A bare
  Python list raises `Could not choose a best candidate function for the function call ts_any(STRING_LITERAL)`.

## 5. Tokenization — a design decision with numbers attached

`log_text` (`template = 'text'` + locale) is the right dictionary for logs because it preserves
technical tokens:

| Input | `ts_lexize('log_text', …)` |
|---|---|
| `R02-M1-N0-C:J12-U11` | `{r02, m1, n0, c:j12, u11}` — digits kept, card:slot kept |
| `RAS KERNEL FATAL ciod: failed to read message prefix` | `{ras, kernel, fatal, ciod, failed, to, read, message, prefix}` |
| `oslo_service.periodic_task` | `{oslo_service.periodic_task}` — **one token** |
| `GET /v2/8a4f9c1d2e3b4a5c6d7e8f9a0b1c2d3e/servers/detail` | `{get, v2, 8a4f9c1d…, servers, detail}` |
| `idoproxydb hit ASSERT condition: ASSERT expression=0` | `{idoproxydb, hit, assert, condition, assert, expression, 0}` |

Consequences to state on stage, because the numbers differ:

- `@@ 'base'` on the current index → **21,212**; on an index built with a non-alpha splitter → **45,306**;
  `ILIKE '%base%'` → **45,351**. `log_text` keeps the path segment `_base` as its own token; a splitter
  that strips `_` turns it into a second `base`. Token match ≠ substring match, by construction.
- `@@ 'ciod'` → 350,567; `ts_starts_with('ciod')` → 350,721.
- `R02-M1-N0-C:J12-U11` is **five** tokens: a phrase search works (`ts_phrase`), a bare `@@` on the
  whole string would not. Query node identity through the **`node` column**, not through body text.

## 6. Role scoping and the search path (measured end to end)

The mechanics behind the 30%-weighted role criterion — and not what either first draft assumed:

| Question | Measured answer |
|---|---|
| Can `GRANT` target an index relation? | **No** — `GRANT SELECT ON bgl_idx` → `relation "bgl_idx" does not exist` |
| What does an index-relation privilege check report? | `permission denied for table bgl_ev` — the check resolves to the **base table** |
| Can a role holding only a view grant search? | **Yes.** A view whose body is `SELECT … FROM bgl_idx`, granted to the role, returned **350,567** matches with a bound parameter |
| Can that role also read the base table? | **No** — `permission denied for table bgl_ev` |
| Does psycopg's normal binding work? | **Yes** — `@@ %s` → 350,567; `@@ ts_phrase(%s)` → 152,734. `ClientCursor` is unnecessary |

**Design consequence.** Role scope is a set of views owned by `postgres`, one per role, with the
filter inside the view definition — SereneDB has **no row security policies** (issue #212) and views
read their sources with the owner's privileges. The manager's view has no `content` column, so a
leaked prompt cannot leak log text. Search access is granted on the **view**, never the table or the
index.

## 7. Bonus track reality check

| Track | Status after probing |
|---|---|
| Workspace indexes (9a) | **At risk.** Both mechanisms it leans on (partial-index restriction, `sdb_metrics` size) do not behave as documented here. Probe-gate it; expect to report a negative result |
| Role-scoped access (9b) | **Sound and now verified end to end** — including the search path (§6). `CREATE ROLE … LOGIN PASSWORD`, `GRANT`, column grants, `SET ROLE` all work |
| Huge datasets (9c) | **Sound.** The engine reads remote Parquet over HTTPS directly (1B rows, 0.8 s for a slice, no download); index the **view** and refresh with `REINDEX INDEX`. Report bytes read and build time |
| Eval harness (9d) | **Sound and cheap.** Golden SQL + tool-selection scoring needs nothing exotic |

## 8. Reproduction

```bash
docker run -d --name serenedb -p 127.0.0.1:7890:7890 -v serenedb-data:/var/lib/serenedb \
  -v "$PWD/data":/data serenedb/serenedb:26.09.1.3
psql -h 127.0.0.1 -p 7890 -U postgres -f sql/10_derive.sql    # 14 s
psql -h 127.0.0.1 -p 7890 -U postgres -f sql/20_indexes.sql   # 5.6 s
psql -h 127.0.0.1 -p 7890 -U postgres -f sql/30_views.sql
psql -h 127.0.0.1 -p 7890 -U postgres -f sql/99_smoke.sql     # headline numbers
```

Loads: **BGL 4,747,963 rows** (zero lines lost), **OpenStack 207,812 of 207,820** (8 unusable),
100% ownership coverage. Full rebuild ≈ **20 seconds**.
