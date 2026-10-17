-- sql/70_bench.sql
-- The huge-datasets bench (team plan §14 item 3): search over data SereneDB does not own, and how
-- much of it each step actually read. Nothing is downloaded to disk; only the index is local.
--
--   A. Remote, metadata only. The organisers' 1-billion-row OTel file (41 GB of Parquet on S3):
--      rows, row groups, size and time span from the footer, with no data pages read.
--   B. Remote, a slice of :seconds seconds (row groups pruned on "TimestampTime"): bytes read per
--      column (EXPLAIN ANALYZE prints the HTTPFS counters), then an inverted index on a VIEW over
--      the slice -- the documented zero-ETL mechanism -- searched by phrase, by service and by
--      trace id, and refreshed with REINDEX.
--   C. The same mechanism at full size on local Parquet: an index on a view over bgl.parquet
--      (4,747,963 rows). It must answer exactly what bgl_idx (the index on the derived table)
--      answers; its build time is set beside a table index with the same columns.
--
-- Four traps this file steps around, all measured on 26.09.1.3 (docs/capabilities.md §11):
--   * enable_external_file_cache is ON by default, and with it on a remote read is NOT pruned: a
--     count over one second of data pulled 600+ MB in 5 minutes, and big cached reads (and the
--     index build) killed the server with SIGSEGV. Every remote read here runs with it OFF;
--   * filter on "TimestampTime" (TIMESTAMPTZ, whole seconds), not "Timestamp" (TIMESTAMPTZ_NS):
--     the nanosecond column needs an explicit cast to compare, and its 1.95 GB is the column a
--     bad plan reads in full;
--   * SeverityText / SeverityNumber stay out of the remote index: every read that included them
--     ended in the same SIGSEGV;
--   * the bench has its own dictionary (bench_text). An index left on log_text would make
--     sql/20_indexes.sql fail ("Cannot drop entry log_text because there are entries that
--     depend on it").
--
-- Run: make bench                      (1-second slice, ~1.5 min)
--      make bench BENCH_SECONDS=10     (make bench-ladder runs 1 and 10 and sizes each index)
--      psql -v remote=0 skips A and B; -v keep=1 leaves the indexes in place.

\set ON_ERROR_STOP on
\pset pager off
\if :{?url}
\else
\set url 'https://public-pme.s3.eu-west-3.amazonaws.com/text_bench/part_000.parquet'
\endif
\if :{?data}
\else
\set data '/data/loghub'
\endif
\if :{?seconds}
\else
\set seconds 1
\endif
\if :{?remote}
\else
\set remote 1
\endif
\if :{?keep}
\else
\set keep 0
\endif
\set slice_from '2025-09-23 00:05:00+00'
\set bgl_file :data '/bgl.parquet'
SELECT (:'slice_from'::TIMESTAMPTZ + (:'seconds' || ' seconds')::INTERVAL)::VARCHAR AS slice_to \gset

DROP INDEX IF EXISTS bench_otel_idx;
DROP VIEW IF EXISTS bench_otel_slice;
DROP INDEX IF EXISTS bench_bgl_idx;
DROP INDEX IF EXISTS bench_bgl_tbl_idx;
DROP VIEW IF EXISTS bench_bgl;
DROP TEXT SEARCH DICTIONARY IF EXISTS bench_text;
CREATE TEXT SEARCH DICTIONARY bench_text (
    template = 'text', locale = 'en_US.UTF-8', case = 'lower',
    stemming = false, accent = false, frequency = true, position = true
);
DROP TABLE IF EXISTS bench_result;
CREATE TEMP TABLE bench_result (step VARCHAR, rows_in_scope BIGINT, seconds DOUBLE, note VARCHAR);

\timing on

\if :remote
\echo ''
\echo '=== A. remote, metadata only: the whole file, no data pages read ==='
SELECT clock_timestamp() AS t0 \gset
SELECT num_rows, num_row_groups, file_size_bytes, round(file_size_bytes / 1e9, 1) AS file_gb
FROM parquet_file_metadata(:'url');
SELECT min(stats_min) AS first_ts, max(stats_max) AS last_ts, sum(row_group_num_rows) AS rows
FROM parquet_metadata(:'url') WHERE path_in_schema = 'TimestampTime';
-- compressed bytes per column: what reading each column in full would fetch
SELECT path_in_schema AS column_name, sum(total_compressed_size) AS compressed_bytes
FROM parquet_metadata(:'url')
WHERE path_in_schema IN ('Body', 'TraceId', 'Timestamp', 'ServiceName', 'TimestampTime')
GROUP BY 1 ORDER BY 2 DESC;
INSERT INTO bench_result
SELECT 'A1 metadata: rows, groups, span, bytes', num_rows,
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'footer only'
FROM parquet_file_metadata(:'url');
SELECT clock_timestamp() AS t0 \gset
SELECT count(*) AS rows_counted FROM read_parquet(:'url');
INSERT INTO bench_result VALUES ('A2 count(*) over the file', 1000000000,
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'answered from row-group metadata');

\echo ''
\echo '=== B. remote slice, row groups pruned on TimestampTime, external file cache OFF ==='
SELECT :'slice_from' AS slice_from, :'slice_to' AS slice_to, :'seconds' AS seconds;
-- the row groups the slice can touch, from their statistics alone
SELECT count(*) AS row_groups_touched, sum(row_group_num_rows) AS rows_in_those_groups
FROM parquet_metadata(:'url')
WHERE path_in_schema = 'TimestampTime'
  AND stats_max::TIMESTAMPTZ >= :'slice_from'::TIMESTAMPTZ
  AND stats_min::TIMESTAMPTZ <  :'slice_to'::TIMESTAMPTZ;
CREATE VIEW bench_otel_slice AS
SELECT "TimestampTime" AS ts, "ServiceName" AS service, "TraceId" AS trace_id, "Body" AS body
FROM read_parquet(:'url')
WHERE "TimestampTime" >= :'slice_from'::TIMESTAMPTZ
  AND "TimestampTime" <  :'slice_to'::TIMESTAMPTZ;
SET enable_external_file_cache = false;

\echo '--- B1 ServiceName alone: HTTPFS "in" is what was actually read (297 MB in the whole file) ---'
SELECT clock_timestamp() AS t0 \gset
EXPLAIN ANALYZE SELECT count(DISTINCT service) FROM bench_otel_slice;
INSERT INTO bench_result VALUES ('B1 read ServiceName of the slice', NULL,
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'bytes in: HTTPFS stats above');
\echo '--- B2 Body alone (9.07 GB in the whole file) ---'
SELECT clock_timestamp() AS t0 \gset
EXPLAIN ANALYZE SELECT count(body) FROM bench_otel_slice;
INSERT INTO bench_result VALUES ('B2 read Body of the slice', NULL,
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'bytes in: HTTPFS stats above');

\echo '--- B3 build: an inverted index on the view over the remote slice ---'
SELECT clock_timestamp() AS t0 \gset
CREATE INDEX bench_otel_idx ON bench_otel_slice
    USING inverted (body bench_text, service, ts, trace_id);
INSERT INTO bench_result SELECT 'B3 build: index on the remote slice view', count(*),
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'body, service, ts, trace_id'
FROM bench_otel_idx;

\echo '--- B4 search the slice: a phrase, then the services it lands on (operator @@ ts_phrase) ---'
SELECT clock_timestamp() AS t0 \gset
SELECT service, count(*) AS hits FROM bench_otel_idx
WHERE body @@ ts_phrase('failed to charge card') GROUP BY service ORDER BY hits DESC, service;
INSERT INTO bench_result SELECT 'B4 phrase + facet on the slice index', count(*),
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'rows = hits; no remote read'
FROM bench_otel_idx WHERE body @@ ts_phrase('failed to charge card');

\echo '--- B5 one request across services: the first trace id behind a hit, then its log lines ---'
SELECT clock_timestamp() AS t0 \gset
SELECT trace_id AS tid FROM bench_otel_idx
WHERE body @@ ts_phrase('failed to charge card') AND trace_id <> ''
ORDER BY trace_id LIMIT 1 \gset
SELECT ts, service, left(body, 70) AS body FROM bench_otel_idx
WHERE trace_id @@ :'tid' ORDER BY ts, service, body LIMIT 12;
INSERT INTO bench_result SELECT 'B5 trace timeline (materialises body)', count(*),
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'trace ' || :'tid'
FROM bench_otel_idx WHERE trace_id @@ :'tid';

\echo '--- B6 refresh: REINDEX INDEX on an unchanged file ---'
SELECT clock_timestamp() AS t0 \gset
REINDEX INDEX bench_otel_idx;
INSERT INTO bench_result VALUES ('B6 REINDEX on the slice, file unchanged', NULL,
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'one refresh pass');
RESET enable_external_file_cache;
\endif

\echo ''
\echo '=== C. zero-ETL at full size: an inverted index on a VIEW over local Parquet ==='
-- a plain SELECT * over the reader with a literal path: a fast-path view, so matched rows can
-- materialise columns the index does not hold (read live from the file by row number)
CREATE VIEW bench_bgl AS SELECT * FROM read_parquet(:'bgl_file');

SELECT clock_timestamp() AS t0 \gset
CREATE INDEX bench_bgl_idx ON bench_bgl USING inverted (content bench_text, component, level, node);
INSERT INTO bench_result SELECT 'C1 build: index on the Parquet view', count(*),
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'view over read_parquet, 4 columns'
FROM bench_bgl_idx;

-- the same four columns on the derived table, for the comparison
SELECT clock_timestamp() AS t0 \gset
CREATE INDEX bench_bgl_tbl_idx ON bgl_ev USING inverted (id, content bench_text, component, level, node);
VACUUM (REFRESH_TABLE) bgl_ev;
INSERT INTO bench_result SELECT 'C2 build: same columns on bgl_ev', count(*),
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'table index + refresh'
FROM bench_bgl_tbl_idx;

\echo '--- C3 the view index must answer what the table indexes answer ---'
SELECT
    (SELECT count(*) FROM bench_bgl_idx     WHERE content @@ ts_phrase('data TLB error interrupt')) AS phrase_view,
    (SELECT count(*) FROM bench_bgl_tbl_idx WHERE content @@ ts_phrase('data TLB error interrupt')) AS phrase_table,
    (SELECT count(*) FROM bgl_idx           WHERE content @@ ts_phrase('data TLB error interrupt')) AS phrase_bgl_idx,
    (SELECT count(*) FROM bench_bgl_idx     WHERE content @@ 'ciod')                              AS term_view,
    (SELECT count(*) FROM bgl_idx           WHERE content @@ 'ciod')                              AS term_bgl_idx;

\echo '--- C4 search timing, view index vs table index (phrase, then a facet on the hits) ---'
SELECT clock_timestamp() AS t0 \gset
SELECT component, count(*) AS hits FROM bench_bgl_idx
WHERE content @@ ts_phrase('data TLB error interrupt') GROUP BY component ORDER BY hits DESC, component;
INSERT INTO bench_result VALUES ('C4 phrase + facet, view index', 152734,
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'operator @@ ts_phrase');
SELECT clock_timestamp() AS t0 \gset
SELECT component, count(*) AS hits FROM bench_bgl_tbl_idx
WHERE content @@ ts_phrase('data TLB error interrupt') GROUP BY component ORDER BY hits DESC, component;
INSERT INTO bench_result VALUES ('C4 phrase + facet, table index', 152734,
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'operator @@ ts_phrase');

\echo '--- C5 materialise columns the index does not hold (date, timestamp), live from the file ---'
SELECT node, date, timestamp, left(content, 40) AS content
FROM bench_bgl_idx WHERE content @@ ts_phrase('data TLB error interrupt')
ORDER BY timestamp, node LIMIT 3;

\echo '--- C6 refresh: REINDEX INDEX on an unchanged file ---'
SELECT clock_timestamp() AS t0 \gset
REINDEX INDEX bench_bgl_idx;
INSERT INTO bench_result VALUES ('C6 REINDEX, file unchanged', 4747963,
       extract(epoch FROM clock_timestamp() - :'t0'::TIMESTAMPTZ), 'one refresh pass');

DROP INDEX bench_bgl_tbl_idx;
VACUUM (REFRESH_TABLE) bgl_ev;

\timing off
\echo ''
\echo '=== summary (wall clock from clock_timestamp(); rows/s only for the builds) ==='
SELECT step, rows_in_scope, round(seconds, 3) AS seconds,
       CASE WHEN step LIKE '%build%' THEN round(rows_in_scope / seconds) END AS rows_per_s,
       note
FROM bench_result ORDER BY step;
\if :remote
\echo '--- extrapolation, NOT a measurement: the remote build rate applied to the whole file ---'
SELECT round(1e9 / (rows_in_scope / seconds) / 3600, 1) AS hours_for_1b_rows_at_b3_rate,
       'network-bound on this machine; the index columns hold 12.9 GB compressed' AS caveat
FROM bench_result WHERE step LIKE 'B3%';
\endif

\if :keep
\echo 'keep=1: bench_otel_idx, bench_bgl_idx and their views stay (bench/run_ladder.sh sizes them)'
\else
DROP INDEX IF EXISTS bench_otel_idx;
DROP VIEW IF EXISTS bench_otel_slice;
DROP INDEX bench_bgl_idx;
DROP VIEW bench_bgl;
DROP TEXT SEARCH DICTIONARY bench_text;
\endif
DROP TABLE bench_result;
