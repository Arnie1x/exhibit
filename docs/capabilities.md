# SereneDB capability matrix — measured on 26.09.1.3

Probed against the live instance, arm64, 2 vCPU / 12 GB, database `postgres`. Every row is a
statement that was executed; PASS/FAIL is what the engine returned, not what the docs say.
Rebuild it with `make probe`; if a row disagrees, the measurement wins and this file changes.

**Re-probed Sat 17 Oct, 09:55 UTC** (Adnan) on a second machine: Windows 11, Docker Desktop
29.7.2, the amd64 build of `serenedb/serenedb:26.09.1.3` (`sha256:018a3187c193…`), 16 vCPU and
7.6 GB for the Docker VM. `scripts/probe_capabilities.sh` now checks **91 rows** against the
outcomes this file states and prints `DRIFT` where they differ: **0 drift** after the two
corrections below (the partial index, §3; search tables, §1). Two consecutive runs gave identical
output apart from timings. Read-only probes run in `postgres` against `bgl_ev`/`bgl_idx`/`os_ev`/
`os_idx`; everything that creates objects runs in a database `exhibit_probe` that the script
recreates and drops.

Why the version matters: `26.10.x` releases are **amd64-only**, so an ARM box is pinned to
**26.09.1.3**. Any docs statement about a feature added after 26.09 may not hold here.

## 1. The architecture question: what can `@@` run against?

This decides the schema, so it was tested four ways.

| Setup | `@@` works? | Evidence |
|---|---|---|
| Plain table, **no** inverted index | **FAIL** | `TSQUERY expression evaluated outside an @@ match against an inverted-indexed column.` |
| Plain table, **with** a `USING inverted` index attached | **FAIL** | same error — the index does not make the table addressable |
| The **index relation itself**, named in `FROM` | **PASS** | `SELECT count(*) FROM probe_idx WHERE content @@ 'parity'` → 1; `FROM bgl_idx` → 121,498 |
| A table created `WITH (storage = 'search')`, inverted index created **before** the rows arrive | **PASS** | `SELECT count(*) FROM probe_search WHERE content @@ 'parity'` → 121,498 |
| Search table, inverted index created **after** the rows (INSERT then `CREATE INDEX`, or CTAS) | **0 rows, no error** | the index and the table both return 0 for `@@ 'parity'`; `REINDEX` refuses (`REINDEX is only supported for view-backed inverted indexes`). Re-probe 17 Oct |
| Search table with **no** inverted index | **FAIL** | `@@ requires an inverted-indexed column on one side` |

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
  name. Fewer moving parts; the table *is* the indexed relation. But the index must exist before
  the rows arrive (an index created on a loaded search table finds nothing), and partial indexes
  ignore their predicate here (§3).
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
| `BM25(<index>.tableoid)` | PASS — 1.92 on the old table, 2.5686417 on `bgl_idx` (first row of an unordered `LIMIT 1`: not a stable value) |
| `percentile_cont(0.95) WITHIN GROUP (ORDER BY col)`, `quantile_cont` | PASS — both 0.3818 |
| `date_bin`, `date_trunc`, `generate_series`, `regr_slope`, `GROUPING SETS`, `GROUP BY ALL` | PASS |
| `date_trunc` on our `TIMESTAMP` columns (`bgl_ev.ts`, `os_ev.ts`) | PASS **without a cast**: `date_trunc('day', min(ts))` → `2005-06-03 00:00:00`. The `::timestamptz` rule is for nanosecond timestamps (the OTel corpus's `TIMESTAMP_NS`) and for `'week'` buckets we cast anyway |
| `GROUP BY` one key on an index relation | dictionary-served: `EXPLAIN SELECT component, count(*) FROM bgl_idx GROUP BY component` shows `TsDict: component` |
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
| Partial inverted index (`… USING inverted (…) WHERE ts >= …`) restricts the index | **Corrected 17 Oct: it restricts on pattern B, and is ignored only on a search table.** The first probe used a search table (pattern A): naming the partial index returned the full count (121,498), `EXPLAIN` on the table query picked the table's own index, timing 4.19 vs 3.99 ms. That still reproduces on a search table. On a plain table with a named index relation (how `bgl_idx` is built) the predicate holds; statements and results below | Workspace indexes are **viable on pattern B** (a partial index per window or team, queried by name). Report the measured build saving, not a query speedup |
| `REINDEX INDEX` on a table-backed index | **FAIL** — `REINDEX is only supported for view-backed inverted indexes` | Rebuild a table-backed index with `DROP INDEX` + `CREATE INDEX` (what `sql/20_indexes.sql` does) |

**The partial-index re-measurement** (17 Oct, `make probe` §5; scratch copy of BGL as
`p_ev(id, ts, content)`, 4,747,963 rows, dictionary `log_text`; window `ts >= TIMESTAMP '2005-12-01'`
holds 424,614 rows):

```sql
CREATE INDEX p_full ON p_ev USING inverted (id, content log_text, ts);                                    -- 1,191 ms
CREATE INDEX p_part ON p_ev USING inverted (id, content log_text, ts) WHERE ts >= TIMESTAMP '2005-12-01'; --   239 ms
VACUUM (REFRESH_TABLE) p_ev;
SELECT count(*) FROM p_full WHERE content @@ 'parity';                                          -- 121,498
SELECT count(*) FROM p_full WHERE content @@ 'parity' AND ts >= TIMESTAMP '2005-12-01';         --  34,056  (truth)
SELECT count(*) FROM p_part WHERE content @@ 'parity';                                          --  34,056  (= truth)
SELECT count(*) FROM p_part WHERE content @@ 'parity' AND ts <  TIMESTAMP '2005-12-01';         --       0
EXPLAIN SELECT count(*) FROM p_part WHERE content @@ 'parity';                                  -- IRESEARCH_SCAN, Index: p_part
```

| Try to break it | Result |
|---|---|
| Partial index created on the **empty** table, rows inserted afterwards | 34,056 — membership applied on INSERT |
| Predicate that matches no row (`ts >= '2026-01-01'`) | 0 |
| `UPDATE` moves one `parity` row from November into the window | 34,057 — membership follows DML, as the bundled docs say |
| Same partial index on a **search table** (`storage = 'search'`, indexes created before the INSERT) | 121,498 named, rows outside the predicate > 0 (87,443 in the probe run, 87,442 in a hand run: unstable by one) — **predicate ignored** |
| Timing, median of 21 runs in one psql session | partial named 1.60–1.84 ms vs full + window 1.96–2.29 ms over three runs: the ranges do not overlap, but the gain is about 0.4 ms per query |

The saving is in the **build**: 239–315 ms for the window against 1,163–1,248 ms for the whole
corpus over three runs, because the partial index holds 424,614 of 4,747,963 rows (8.9%). The
bundled 26.09.1.3 docs agree (`sql/statements/create_index/inverted.md`, "Partial indexes"):
*queries against the index only ever see matching rows*. `sdb_indexes().sql` does **not** show the
predicate (it prints `CREATE INDEX p_part ON public.p_ev USING inverted ();`), so record each
workspace index's predicate ourselves.

**The dictionary re-measurement** (17 Oct, `make probe` §3–4) — the row above holds:

| Statement | Result |
|---|---|
| `CREATE TEXT SEARCH DICTIONARY probe_a AS split_text(case := 'lower') WITH (frequency, position, offset)` | `ERROR: syntax error at or near "AS"` |
| `CREATE TEXT SEARCH DICTIONARY probe_b (template = 'text', locale = 'en_US.UTF-8', case = 'lower', stemming = false, accent = false, frequency = true, position = true)` | PASS |
| the same with `offset = true` | PASS |
| `(template = 'split_by_non_alpha', case = 'lower', frequency = true, norm = true, position = true)` | PASS |
| `ts_lexize('log_text', …)` on the five inputs in §5 | identical to the §5 table, token for token |
| `ts_lexize('log_text', 'failed failures interrupts')` | `{failed,failures,interrupts}` — `stemming = false` holds (a `stemming = true` copy gives `{fail,failur,interrupt}`) |
| `bgl_idx … @@ 'PARITY'` | 121,498, same as `'parity'` — `case = 'lower'` applies to the query too |
| bundled docs, `sdb_docs.search('CREATE TEXT SEARCH DICTIONARY template', 3)` | `sql/statements/create_text_search_dictionary/index.md`: "A dictionary must name exactly one template through the TEMPLATE option" — the parenthesised form is the documented one on this version |
| `PREPARE name(VARCHAR) AS … $1` in psql | `TypeList for prepared statement has not been implemented` | A **psql** limitation only — psycopg's binding works (§6). Do not conclude parameters are broken from it |
| `CREATE FUNCTION … LANGUAGE sql SECURITY DEFINER` enforces owner privileges | **Not honoured** — the definer function still failed with `permission denied for table bgl_ev` | Parameterised search is a **view + an outer predicate**, never a definer function |

## 4. Corrected: smaller items

- **`statement_timeout` is accepted and not enforced** (17 Oct, found by `sql-verifier`, re-checked):
  `SET statement_timeout = '1ms'` returns `WARNING: parameter "statement_timeout" is accepted for
  compatibility but is not enforced by serened`, `SHOW` reports `1ms`, and a 200 ms query completes.
  The 30 s limit on tool paths must be enforced by the client (cancel the query from a timer).
- **`VARCHAR(n)` is accepted** — `CREATE TABLE probe_vc (a VARCHAR(10))` succeeded, and 20 characters
  stored all 20 (`length(a)` = 20). "Never `VARCHAR(n)`" is still right, but for the correct reason:
  **it does not enforce.** Nobody should write validation that assumes a length limit.
- **`BM25()` with no arguments does not exist**; `BM25(<index>.tableoid)` does.
- **`ts_offsets` / `ts_highlight` require an `@@` in the same sub-query** — that is what the error says.
- Confirmed absent: `to_timestamp(text)` (epoch only), `to_char`, `to_date`.
- `ts_any` / `ts_all` with a **bound parameter** need a cast: `ts_any(%s::TSQUERY[])` → 382,098. A bare
  Python list raises `Could not choose a best candidate function for the function call ts_any(STRING_LITERAL)`.
- **`= ANY(%s)` with a bound list needs the same cast** (17 Oct, Adnan, psycopg 3): a bare list raises
  `FeatureNotSupported: UNNEST not supported here`; `instance_id = ANY(%s::VARCHAR[])` and
  `list_contains(%s::VARCHAR[], instance_id)` both work (2 of 2 rows for two instance IDs).
- **`NULL`s sort last in both directions** (17 Oct, Adnan): `ORDER BY spawn_s DESC` over
  `os_instance_durations` returns 50.72 first and `ASC` returns 10.12 first; the 3 `NULL` rows come
  last both times. PostgreSQL puts them **first** under `DESC`. Write `NULLS LAST` explicitly, so the
  statement reads the same on either engine.
- **`arg_max` breaks ties by scan order, not deterministically** (17 Oct, Adnan): over a 1–1 tie (the
  signature `ciodb exited normally with exit code {n}`: one `MASNORM` line, one `-` line) it returned a
  different label on consecutive runs, so a count built on it moved by one (TP 348,455, then 348,454).
  Pick a winner with `row_number() OVER (PARTITION BY … ORDER BY n DESC, <key>)` instead.

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
| Can a LOGIN role without a password connect? | **No, not even over loopback** (re-measured 17 Oct, Windows box): `psql -h 127.0.0.1 -U exhibit_lead` inside the container → `password authentication failed for user "exhibit_lead"`. Default HBA (docs, *Client Authentication › The default posture*): only `postgres` is `trust` on unix socket and loopback; every other role needs a SCRAM password, and "a role with no password cannot log in at all". Reach the role views by connecting as `postgres` and running `SET ROLE exhibit_<role>` (what `sql/50_roles.sql` and `sql/90_queries.sql` do), or give each role a password |
| Does the host reach `postgres` without a password through `-p 127.0.0.1:7890`? | **No on Docker Desktop (Windows)**: psycopg from the host → `password authentication failed for user "postgres"`, because the forwarded connection arrives from the Docker bridge, not the container's loopback; the server log reads `network auth using per-role catalog passwords`. Inside the container (`docker exec … psql -h 127.0.0.1`) it is trusted. Fix is a choice: `POSTGRES_PASSWORD` on first start, `ALTER ROLE postgres PASSWORD …`, or `SET hba = '…'` trusting the bridge range. Not changed here |

**Design consequence.** Role scope is a set of views owned by `postgres`, one per role, with the
filter inside the view definition — SereneDB has **no row security policies** (issue #212) and views
read their sources with the owner's privileges. The manager's view has no `content` column, so a
leaked prompt cannot leak log text. Search access is granted on the **view**, never the table or the
index.

## 7. Bonus track reality check

| Track | Status after probing |
|---|---|
| Workspace indexes (9a) | **Viable on pattern B since the 17 Oct re-probe.** A partial index restricts when it is named (34,056 = the windowed count) and builds in about a fifth of the time (239 vs 1,191 ms for 8.9% of the rows); queries gain about 0.4 ms. Still no size metric (`sdb_metrics`), so report build time and row counts, never bytes. The bonus order in the team plan §14 is unchanged |
| Role-scoped access (9b) | **Sound and now verified end to end** — including the search path (§6). `CREATE ROLE … LOGIN PASSWORD`, `GRANT`, column grants, `SET ROLE` all work |
| Huge datasets (9c) | **Sound.** The engine reads remote Parquet over HTTPS directly (1B rows, 0.8 s for a slice, no download); index the **view** and refresh with `REINDEX INDEX`. Report bytes read and build time |
| Eval harness (9d) | **Sound and cheap.** Golden SQL + tool-selection scoring needs nothing exotic |

## 8. Stage 3 — windowing, change detection, and two traps

Measurements taken while building the analysis tools (17 Oct), each one a decision rather than a
curiosity:

| Question | Measured answer |
|---|---|
| Can the episode **gap** be a bound parameter? | **Yes** — `INTERVAL '1 minute' * %s` binds (`5` → `00:05:00`). This is what makes the gap a real parameter instead of string-spliced SQL |
| Does `date_bin` take two arguments? | **No.** `date_bin(INTERVAL, TIMESTAMP)` → `UndefinedFunction`; the signature is `date_bin(stride INTERVAL, source TIMESTAMP, origin TIMESTAMP)`. Buckets are therefore aligned to **each corpus's own start** (2005-06-03 / 2017-05-14) rather than to 1970 |
| Does `date_trunc` need a cast? | **No** on our `TIMESTAMP` columns (`date_trunc('day', ts)` returns 2005-06-11 00:00:00 for the burst day). The `::timestamptz` cast is only for nanosecond timestamps and for `'week'` |
| Does `FULL OUTER JOIN` work? | **Yes** — the foreground/baseline join in `what_changed` depends on it |
| `round(x, 2)`, `nullif`, `coalesce`, `count(DISTINCT …)`? | All work; used in the rate-ratio and blast-radius expressions |
| Can `ts_dict_agg` give significant terms? | **Not usefully.** `ts_dict_agg(content)` returns **per-term identifier arrays**: one call over ~21,000 matching lines returned roughly **4.8 MB** of output. `ts_dict_count` takes exactly one argument (`col0 ANY`) and returns `INTEGER[]`, so it cannot be paired with terms. Neither yields a bounded term→count map. `what_changed` therefore measures change at **signature** level — see `PLAN.md` §7 |
| Does a statement with no result set break the driver? | **Yes** — `fetchall()` on an `INSERT` raises *"the last operation didn't produce a result"*, and a broad `except` in the ledger swallowed it into a note: the evidence ledger silently recorded **nothing** until this was found by an acceptance check. Writes go through `db.execute`, and the checks now assert that a ledger row exists |
| Is the result order stable? | **No** for ties. `ORDER BY lines DESC` over 19,250 incidents — thousands of them one line long — can come back in a different sequence between runs, which made the ledger's hash report a false MISMATCH. The hash is now **order-independent** (rows are sorted before hashing); order is presentation, content is the claim |
| Is an index relation's column set the base table's? | **No.** `bgl_idx` = `id, ts, alert_category, is_alert, node, node_kind, rack, midplane, nodecard, component, level, level_rank, template_id, team, content` — **no `signature`** (that lives on `bgl_sig`); `os_idx` has no `problem`. A tool that walks lines through the index must name columns the *index* has |
| Anything else that bites? | `owner_map` stores `'BGL'`/`'OpenStack'` capitalised, so an equality filter must case-fold **both** sides |

Episode coalescing, measured through the tool rather than beside it: **22,002** incidents at a
1-minute gap, **19,250** at 5 (equal to the prebuilt view — the tool recomputes it), **14,479** at
60, and **1,377** when the failure domain is dropped. The burst itself is **152,182 `KERNDTLB`
lines** in one incident on one node, while **152,183** is every alert line on that node that day
(152,182 + 1 `KERNMC`) — two different cuts of the same six hours, and both are guarded by checks so
neither can be "corrected" into the other.

### 8.1 A blast-radius column that reads 0 for a reason

Instance coverage is the one place where the OpenStack corpus quietly changes what a number *means*,
so it is measured rather than assumed:

| relation | lines | carry an instance id |
|---|---|---|
| `os_sig`, all lines | 207,812 | 51,553 (24.8%) |
| `os_sig`, `level <> 'INFO'` (the ranking's scope) | 3,306 | **0** |
| `os_incident` (the lead's relation), 68 incidents | 68 rows | **max(instances) = 0** |
| `mgr_os_risk.requests_affected` (the manager's) | 5 problems | **max 45, sum 68** |
| `bgl_incident.nodes` (for contrast) | 19,250 incidents | max 520 |

The instance id sits on normal-traffic lines and on none of the error lines, so:

1. `episodes` still returns the 0 — it is measured and true — but the answer carries a note saying
   the blast radius is **unmeasurable in instances rather than genuinely zero**, and to read the
   service and the file paths instead. Without it, "0 nodes" in a demo reads as a join that failed.
2. `top_signatures(by='nodes')` on OpenStack is **refused** with that reasoning, because ranking on
   a column that is 0 for every row ranks nothing. The alternative is named in the refusal.
3. The manager's column is renamed to `requests_affected` — its expression is
   `max(requests_affected)`, and a request count is not a machine count. A column named `nodes`
   that holds 45 requests is exactly the kind of false label this project exists to avoid.

All three are guarded by acceptance checks, including one asserting the note does **not** appear for
BGL, where every alert line names a node.

### 8.2 A "signature" group that was returning the label

`bgl_ev` has no `signature` column. The engineer's registry mapped `group_by="signature"` to
`alert_category` — BGL's *label* — and `group_by="signature"` on OpenStack to `logger`. Both are
coarser than a signature, and the label is the one thing this project exists to distrust: measured,
`count_events(group_by="category")` puts **4,399,503 of 4,747,963 lines under the single label `-`**,
while `group_by="signature"` on the same rows shows `generating core.{n}` at 1,706,751 and a long tail
underneath it. The engineer now reads `bgl_sig` / `os_sig` (the same rows with the masked signature
added), `signature` means the masked signature, and `category` is the label when you want it.

`episodes` also gained a `signature=` filter, which is how the DTLB headline was cross-checked:
**132 / 117 / 57** incidents at gaps of 60 / 300 / 3,600 seconds, computed by the teammate's literal
SQL and by this tool's bound parameters, agreeing exactly. The filter is refused for the manager,
whose relation names problems by `signature_id` rather than by text — a refusal that says so beats a
filter that silently matches nothing.

### 8.3 Two failures a green test suite did not catch

Both were found by building and running, not by reading, and both are about the boundary *between*
components rather than any one component:

1. **Seven of ten tool calls were not JSON-serialisable.** The engine returns `DECIMAL` for
   `sum(...)`, `date` for a truncated bucket, `datetime` for a timestamp, and `timedelta` for a
   difference between two of them. `json.dumps` accepts none of those four. Every acceptance check
   stayed green through it because the checks compare Python objects, and the MCP layer's pydantic
   models were quietly absorbing what a strict client would reject. The manager's ranked list —
   the exact artifact W1 turns on — raised `TypeError` on a plain client. Normalisation now lives in
   the shared envelope (`tools._jsonable`), and a check dumps one call per tool per persona.
   The knock-on effect mattered too: once the envelope normalised, `verify_evidence` reported
   MISMATCH on identical answers (recorded rows were normalised, re-run rows were raw), so the
   ledger's hash canonicalises both forms — a Decimal and an int now hash identically.
2. **The server forwarded arguments positionally.** Adding one parameter to a tool's signature
   silently shifted every later argument: `episodes(..., limit=3)` arrived as `signature=3`, and the
   server answered `Could not convert string 'rts panic! - stopping execution' to INT16 ... WHERE
   signature = $2`. No unit-level check could see this — the function was called correctly in every
   test and incorrectly by its only real caller. Every wrapper now forwards by keyword, and the
   stock-client check calls the tools over MCP, which is where this class of bug lives.

## 8.4 Why a host connection needed a password (and the one flag that removes it)

The container's `/entrypoint.sh` writes its HBA only when `SERENEDB_HOST_AUTH_METHOD` is set:

```
local all all <method>
host  all all 0.0.0.0/0 <method>
host  all all ::/0      <method>
```

Without it the default applies, which trusts `postgres` on the container's own loopback and demands a
password from anywhere else — including a **host** connection through Docker's port forwarding, which
the container sees as coming from the bridge. That is why `psql -h 127.0.0.1 -p 7890 -U postgres`
works on one box and fails with `password authentication failed` on another, with no password set
anywhere. Recognised values are `trust | reject | password | md5 | scram-sha-256`; **any other value
logs a parse error and silently falls back to requiring a password**, so a typo costs access rather
than failing loudly. `trust` is the laptop-and-demo setting and is only defensible because the port
is published to `127.0.0.1` (and, on our box, the Tailscale address), not `0.0.0.0`.

Related, for a judge without a host `psql`: `psql -f sql/x.sql` needs the file path to exist *inside*
whatever runs psql, which `docker exec` breaks. Every Makefile target now uses `< sql/x.sql`, which
works with a host client and with `PSQL='docker exec -i serenedb psql …'` alike.

## 9. The answer lints, and the eval that scores them

The plan promised two rules in prose (`docs/build-plan.md` §6): a manager answer may not claim money,
downtime, customers, revenue or an SLA, and every figure in an answer must cite evidence that
resolves. Prose is a promise; `src/exhibit/lint.py` is the rule, and `make eval` is the score.

**The manager lint.** Scanning stops at quoted spans, because the rule bans *claiming*, not
*quoting*: `the logs say "Time out on <SLA>"` passes, `this costs $4,000 in downtime` is rejected
with one finding per term. Measured, through the MCP surface: 2 rejections on the first, 0 on the
second.

**The numeric lint.** Every bullet in the *Observed* block that carries a figure must cite an
evidence id; with `deep=true` each cited statement is re-run and the figure has to be supported by
its result. What counts as supported is the interesting part, and it took two iterations to get
honest:

* a value in the rows returned (the obvious case);
* an aggregate of the statement's own result — `sum`, `min`, `max` of any numeric column, or its row
  count. Without this, "348,460 alert lines in total" flagged as unsupported, because a total is not
  a value in any one row. A total the statement does not produce is exactly what the lint is for, so
  the rule is not "accept totals", it is "accept the arithmetic this statement actually supports";
* the total the envelope itself reported, recorded in the ledger's `total_matches` column. A paged
  statement returns a page; `verify_evidence` compares the page, and the total is a claim the page
  carries. Both are in the record, so both are checkable.

A hyphenated compound (`5-minute gap`, `60-minute window`) is a method statement and is not treated
as a data figure; a standalone figure (`124 days`) is. That distinction came from a false positive,
not from theory.

**The eval** (`make eval` → 15/15):

| | |
|---|---|
| questions | 15 across the three roles, from the brief's own shapes |
| figures checked | 19, every one compared against a hand-written statement in `evals/golden.sql` — not the SQL the tools build, so a tool's SQL cannot silently move a number |
| refusals exercised | 6 assertions across 3 negative questions (the wrong-role request must be refused, by name, with a reason) |
| the chain | each question's answer is built from the values that came back, cites the evidence id, and must pass the lints — a figure that does not resolve fails the question |

What the eval does **not** do is score a model's prose, and it says so in its own docstring. It
scores the part that has to be true.

Two real defects surfaced by building it, both at the seams rather than in any single tool:

1. `search_logs`, `count_events` and `describe_data` handed out evidence ids without recording
   them, so a citation of their answers could not be checked at all. All three now record.
2. `verify_evidence` *raised* on a refusal's id ("the last operation didn't produce records")
   instead of reporting that refusals are records of a non-answer. A refusal is still an answer,
   and now it verifies like one.

## 10. Reproduction

```bash
docker run -d --name serenedb -p 127.0.0.1:7890:7890 -e SERENEDB_HOST_AUTH_METHOD=trust \
  -v serenedb-data:/var/lib/serenedb -v "$PWD/data":/data serenedb/serenedb:26.09.1.3
psql -h 127.0.0.1 -p 7890 -U postgres -v data=/data/loghub -v map=/data/ownership.csv \
     -f sql/10_derive.sql                                       # 14 s (8.7 s on 16 vCPU)
psql -h 127.0.0.1 -p 7890 -U postgres -f sql/20_indexes.sql   # 5.6 s (2.4 s)
psql -h 127.0.0.1 -p 7890 -U postgres -f sql/30_views.sql
psql -h 127.0.0.1 -p 7890 -U postgres -f sql/99_smoke.sql     # headline numbers
bash scripts/probe_capabilities.sh                            # this file, re-measured (~90 s)
```

No `psql` or `make` on the host (Windows): use the client inside the container and pipe the
file in, with Git Bash's path rewriting off (it turns `/data/...` into `C:/Program Files/Git/data/...`):

```bash
export MSYS_NO_PATHCONV=1
docker exec -i serenedb psql -h 127.0.0.1 -p 7890 -U postgres -v ON_ERROR_STOP=1 \
  -v data=/data/loghub -v map=/data/ownership.csv -f - < sql/10_derive.sql
PSQL='docker exec -i serenedb psql -h 127.0.0.1 -p 7890 -U postgres' bash scripts/probe_capabilities.sh
```

Loads: **BGL 4,747,963 rows** (zero lines lost), **OpenStack 207,812 of 207,820** (8 unusable),
100% ownership coverage. Full rebuild ≈ **20 seconds**.
