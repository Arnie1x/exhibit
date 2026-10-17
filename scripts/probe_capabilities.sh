#!/usr/bin/env bash
# scripts/probe_capabilities.sh  (`make probe`)
#
# Re-measures the rows of docs/capabilities.md against the live engine and flags DRIFT wherever
# the engine and the doc disagree. Each probe states the outcome the doc claims (ok / err, and a
# first value where the doc gives one); the measurement wins, so a DRIFT line means the doc changes.
#
# Read-only probes run in the main database against bgl_ev / bgl_idx / os_ev / os_idx, so run
# `make bootstrap` first. Every probe that creates something runs in the database exhibit_probe,
# which is recreated at the start and dropped at the end (exhibit_scratch is left alone for
# hand tests); probe roles are dropped at the end.
#
#   bash scripts/probe_capabilities.sh                     # host psql
#   PSQL='docker exec -i serenedb psql -h 127.0.0.1 -p 7890 -U postgres' \
#     bash scripts/probe_capabilities.sh                   # no psql on the host (Windows)
#
# Exit status: 0 when every row matches the doc, 1 when any row drifted.

set -u
export MSYS_NO_PATHCONV=1                    # Git Bash: keep /data/... as written
PSQL=${PSQL:-psql -h 127.0.0.1 -p 7890 -U postgres}
DATA=${DATA:-/data/loghub}                   # as the SereneDB container sees it
SCRATCH=exhibit_probe              # its own database, recreated every run and dropped at the end
ROWS=0; DRIFT=0

sql_in() {   # db -- run stdin as one psql session, print results only, keep psql's exit status
  local out rc
  out=$($PSQL -d "$1" -q -tA -v ON_ERROR_STOP=1 -f - 2>&1); rc=$?
  printf '%s\n' "$out" | grep -v -e 'WARNING:' -e '^$'
  return $rc
}

# probe <label> <ok|err> <expected last line | ~substring | ''> <sql> [db]
probe() {
  local label=$1 expect=$2 want=$3 sql=$4 db=${5:-postgres} out status got verdict=match
  if out=$(printf '%s\n' "$sql" | sql_in "$db"); then status=ok; else status=err; fi
  if [[ $want == '~'* ]]; then
    want=${want:1}
    got=$(printf '%s\n' "$out" | grep -m1 -o -F -- "$want")
  else
    got=$(printf '%s\n' "$out" | tail -1 | tr -s ' ' | cut -c1-90)
  fi
  [[ $status == err ]] && got=$(printf '%s\n' "$out" | grep -m1 -e 'ERROR' | cut -c1-90)
  if [[ $status != "$expect" ]] || [[ $status == ok && -n $want && $got != "$want" ]]; then
    verdict=DRIFT; DRIFT=$((DRIFT + 1))
  fi
  ROWS=$((ROWS + 1))
  printf '%-5s %-4s %-50s %s\n' "$verdict" "$status" "$label" "$got"
  [[ $verdict == DRIFT && -n $want ]] && printf '%61s doc says: %s\n' '' "$want"
  return 0
}

median_ms() {   # db runs sql -- median of psql \timing over <runs> executions in one session
  { echo '\timing on'; for _ in $(seq "$2"); do printf '%s\n' "$3"; done; } |
    $PSQL -d "$1" -q -tA -f - 2>&1 | sed -n 's/^Time: \([0-9.]*\) ms.*/\1/p' | sort -n |
    awk '{a[NR] = $1} END {if (NR) printf "%.2f", (NR % 2 ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2)}'
}

build_ms() {    # db sql -- wall-clock of one statement, from psql \timing
  printf '\\timing on\n%s\n' "$2" | $PSQL -d "$1" -q -tA -f - 2>&1 | sed -n 's/^Time: \([0-9.]*\) ms.*/\1/p' | tail -1
}

info() { printf 'info       %-50s %s\n' "$1" "$2"; }

echo "probe: $($PSQL -d postgres -tA -c 'SELECT version()' 2>&1 | head -1)"
echo "       $(date -u '+%Y-%m-%d %H:%M UTC') · main db postgres · scratch db $SCRATCH · data $DATA"
if ! $PSQL -d postgres -tA -c 'SELECT count(*) FROM bgl_ev' >/dev/null 2>&1; then
  echo "bgl_ev is missing: run make bootstrap first"; exit 2
fi

# ------------------------------------------------------------------------------ scratch setup
# A fresh scratch database every run, so no leftover object can change a result.
if ! sql_in postgres <<<"DROP DATABASE IF EXISTS $SCRATCH; CREATE DATABASE $SCRATCH;" >/dev/null ||
   ! sql_in "$SCRATCH" <<SQL >/dev/null; then
CREATE TEXT SEARCH DICTIONARY log_text (template = 'text', locale = 'en_US.UTF-8', case = 'lower',
    stemming = false, accent = false, frequency = true, position = true);
CREATE TABLE p_ev AS
SELECT row_number() OVER () AS id, "timestamp"::timestamp AS ts, content
FROM read_parquet('$DATA/bgl.parquet');
SQL
  echo "scratch setup failed (is $DATA/bgl.parquet visible to the server?)"; exit 2
fi

echo; echo "############ 1. WHAT CAN @@ RUN AGAINST? (doc §1) ############"
probe "@@ on the plain table bgl_ev"                 err "" "SELECT count(*) FROM bgl_ev WHERE content @@ 'parity'"
probe "@@ on the index relation bgl_idx"             ok  121498 "SELECT count(*) FROM bgl_idx WHERE content @@ 'parity'"
probe "@@ on a search table, index before INSERT"    ok  121498 "
CREATE TABLE p_search (id BIGINT, ts TIMESTAMP, content VARCHAR) WITH (storage = 'search');
CREATE INDEX p_search_idx ON p_search USING inverted (id, content log_text, ts);
CREATE INDEX p_search_part ON p_search USING inverted (id, content log_text, ts) WHERE ts >= TIMESTAMP '2005-12-01';
INSERT INTO p_search SELECT id, ts, content FROM p_ev;
VACUUM (REFRESH_TABLE) p_search;
SELECT count(*) FROM p_search WHERE content @@ 'parity';" "$SCRATCH"
probe "search table, index created after the rows"   ok  0 "
CREATE TABLE p_search_late (id BIGINT, ts TIMESTAMP, content VARCHAR) WITH (storage = 'search');
INSERT INTO p_search_late SELECT id, ts, content FROM p_ev;
CREATE INDEX p_search_late_idx ON p_search_late USING inverted (id, content log_text, ts);
VACUUM (REFRESH_TABLE) p_search_late;
SELECT count(*) FROM p_search_late WHERE content @@ 'parity';" "$SCRATCH"
probe "same, via CTAS"                               ok  0 "
CREATE TABLE p_search_ctas WITH (storage = 'search') AS SELECT id, ts, content FROM p_ev;
CREATE INDEX p_search_ctas_idx ON p_search_ctas USING inverted (id, content log_text, ts);
VACUUM (REFRESH_TABLE) p_search_ctas;
SELECT count(*) FROM p_search_ctas_idx WHERE content @@ 'parity';" "$SCRATCH"
probe "search table without any inverted index"      err "" "
CREATE TABLE p_search_bare (id BIGINT, content VARCHAR) WITH (storage = 'search');
INSERT INTO p_search_bare VALUES (1, 'parity error');
SELECT count(*) FROM p_search_bare WHERE content @@ 'parity';" "$SCRATCH"
probe "REINDEX on a table-backed index"              err "" "REINDEX INDEX p_search_late_idx" "$SCRATCH"

echo; echo "############ 2. SEARCH / TEXT ANALYSIS (doc §2, §4) ############"
probe "ts_dict_agg (facets)"                         ok  "" "SELECT count(*) FROM (SELECT unnest(ts_dict_agg(component)) FROM bgl_idx) t"
probe "ts_dict_count"                                ok  "" "SELECT count(*) FROM (SELECT unnest(ts_dict_count(component)) FROM bgl_idx) t"
probe "GROUP BY one key is dictionary-served"        ok  "~TsDict: component" "EXPLAIN SELECT component, count(*) FROM bgl_idx GROUP BY component"
probe "ts_offsets without @@ in the sub-query"       err "" "SELECT ts_offsets(content) FROM bgl_idx LIMIT 1"
probe "ts_highlight with @@"                         ok  "instruction cache <b>parity</b> error corrected" "SELECT ts_highlight(content, ts_offsets(content)) FROM bgl_idx WHERE content @@ 'parity' LIMIT 1"
probe "BM25(bgl_idx.tableoid)"                       ok  "" "SELECT BM25(bgl_idx.tableoid) FROM bgl_idx WHERE content @@ 'parity' LIMIT 1"
probe "BM25() with no argument"                      err "" "SELECT id FROM bgl_idx WHERE content @@ 'parity' ORDER BY BM25() DESC LIMIT 1"
probe "ts_phrase('data TLB error interrupt')"        ok  152734 "SELECT count(*) FROM bgl_idx WHERE content @@ ts_phrase('data TLB error interrupt')"
probe "ts_any(['data','storage'])"                   ok  274012 "SELECT count(*) FROM bgl_idx WHERE content @@ ts_any(['data','storage'])"
probe "ts_all(['data','storage'])"                   ok  63493  "SELECT count(*) FROM bgl_idx WHERE content @@ ts_all(['data','storage'])"
probe "ts_levenshtein('parity', 1)"                  ok  121498 "SELECT count(*) FROM bgl_idx WHERE content @@ ts_levenshtein('parity', 1)"
probe "ts_starts_with('instr')"                      ok  208851 "SELECT count(*) FROM bgl_idx WHERE content @@ ts_starts_with('instr')"
probe "ts_regexp('instru.*')"                        ok  202310 "SELECT count(*) FROM bgl_idx WHERE content @@ ts_regexp('instru.*')"
probe "to_tsquery('data AND TLB')"                   ok  152734 "SELECT count(*) FROM bgl_idx WHERE content @@ to_tsquery('data AND TLB')"
probe "websearch_to_tsquery('data TLB')"             ok  152734 "SELECT count(*) FROM bgl_idx WHERE content @@ websearch_to_tsquery('data TLB')"
probe "sdb_docs.search(query, max_hits)"             ok  "" "SELECT count(*) FROM sdb_docs.search('inverted index', 3)"
probe "sdb_docs.search(query) one argument"          err "" "SELECT * FROM sdb_docs.search('inverted index')"
probe "PREPARE ... \$1 in psql"                        err "" "PREPARE p(VARCHAR) AS SELECT count(*) FROM bgl_idx WHERE content @@ \$1"

echo; echo "############ 3. DICTIONARY (doc §3 row 1, §5) ############"
probe "dict: AS split_text(...) WITH (...) form"         err "" "CREATE TEXT SEARCH DICTIONARY probe_a AS split_text(case := 'lower') WITH (frequency, position, offset)" "$SCRATCH"
probe "dict: parenthesised template='text' form"     ok  "" "
DROP TEXT SEARCH DICTIONARY IF EXISTS probe_b;
CREATE TEXT SEARCH DICTIONARY probe_b (template = 'text', locale = 'en_US.UTF-8', case = 'lower',
    stemming = false, accent = false, frequency = true, position = true);
DROP TEXT SEARCH DICTIONARY probe_b;" "$SCRATCH"
probe "dict: template='split_by_non_alpha', norm"    ok  "" "
DROP TEXT SEARCH DICTIONARY IF EXISTS probe_c;
CREATE TEXT SEARCH DICTIONARY probe_c (template = 'split_by_non_alpha', case = 'lower', frequency = true, norm = true, position = true);
DROP TEXT SEARCH DICTIONARY probe_c;" "$SCRATCH"
probe "dict: offset = true accepted"                 ok  "" "
DROP TEXT SEARCH DICTIONARY IF EXISTS probe_d;
CREATE TEXT SEARCH DICTIONARY probe_d (template = 'text', locale = 'en_US.UTF-8', case = 'lower',
    stemming = false, accent = false, frequency = true, position = true, offset = true);
DROP TEXT SEARCH DICTIONARY probe_d;" "$SCRATCH"
probe "lexize: R02-M1-N0-C:J12-U11"                  ok  "{r02,m1,n0,c:j12,u11}" "SELECT ts_lexize('log_text', 'R02-M1-N0-C:J12-U11')"
probe "lexize: RAS KERNEL FATAL ciod: ..."             ok  "{ras,kernel,fatal,ciod,failed,to,read,message,prefix}" "SELECT ts_lexize('log_text', 'RAS KERNEL FATAL ciod: failed to read message prefix')"
probe "lexize: oslo_service.periodic_task"           ok  "{oslo_service.periodic_task}" "SELECT ts_lexize('log_text', 'oslo_service.periodic_task')"
probe "lexize: GET /v2/<tenant>/servers/detail"      ok  "{get,v2,8a4f9c1d2e3b4a5c6d7e8f9a0b1c2d3e,servers,detail}" "SELECT ts_lexize('log_text', 'GET /v2/8a4f9c1d2e3b4a5c6d7e8f9a0b1c2d3e/servers/detail')"
probe "lexize: idoproxydb hit ASSERT ..."              ok  "{idoproxydb,hit,assert,condition,assert,expression,0}" "SELECT ts_lexize('log_text', 'idoproxydb hit ASSERT condition: ASSERT expression=0')"
probe "lexize: stemming = false keeps 'failed'"      ok  "{failed,failures,interrupts}" "SELECT ts_lexize('log_text', 'failed failures interrupts')"
probe "case = 'lower': @@ 'PARITY'"                  ok  121498 "SELECT count(*) FROM bgl_idx WHERE content @@ 'PARITY'"

echo; echo "############ 4. TOKENIZATION COUNTS (doc §5) ############"
probe "os_idx @@ 'base' (log_text)"                  ok  21212  "SELECT count(*) FROM os_idx WHERE content @@ 'base'"
probe "os_ev ILIKE '%base%' (substring, not tokens)" ok  45351  "SELECT count(*) FROM os_ev WHERE content ILIKE '%base%'"
probe "@@ 'base' with a split_by_non_alpha index"    ok  45306  "
DROP TEXT SEARCH DICTIONARY IF EXISTS probe_na;
CREATE TEXT SEARCH DICTIONARY probe_na (template = 'split_by_non_alpha', case = 'lower', frequency = true, norm = true, position = true);
DROP TABLE IF EXISTS p_os CASCADE;
CREATE TABLE p_os AS SELECT row_number() OVER () AS id, message AS content FROM read_parquet('$DATA/openstack.parquet');
CREATE INDEX p_os_na ON p_os USING inverted (id, content probe_na);
VACUUM (REFRESH_TABLE) p_os;
SELECT count(*) FROM p_os_na WHERE content @@ 'base';" "$SCRATCH"
probe "bgl_idx @@ 'ciod'"                            ok  350567 "SELECT count(*) FROM bgl_idx WHERE content @@ 'ciod'"
probe "bgl_idx ts_starts_with('ciod')"               ok  350721 "SELECT count(*) FROM bgl_idx WHERE content @@ ts_starts_with('ciod')"

echo; echo "############ 5. PARTIAL INVERTED INDEX (doc §3 row 3) ############"
# Pattern B (plain table + named index relation, as bgl_idx). Truth for the window is the full
# index plus the same predicate; the partial index must return exactly that with no predicate.
full_ms=$(build_ms "$SCRATCH" "CREATE INDEX p_full ON p_ev USING inverted (id, content log_text, ts);")
part_ms=$(build_ms "$SCRATCH" "CREATE INDEX p_part ON p_ev USING inverted (id, content log_text, ts) WHERE ts >= TIMESTAMP '2005-12-01';")
sql_in "$SCRATCH" <<<"VACUUM (REFRESH_TABLE) p_ev;" >/dev/null
probe "rows in the window (table, no index)"         ok  424614 "SELECT count(*) FROM p_ev WHERE ts >= TIMESTAMP '2005-12-01'" "$SCRATCH"
probe "full index, all rows"                         ok  121498 "SELECT count(*) FROM p_full WHERE content @@ 'parity'" "$SCRATCH"
probe "full index + window predicate (truth)"        ok  34056  "SELECT count(*) FROM p_full WHERE content @@ 'parity' AND ts >= TIMESTAMP '2005-12-01'" "$SCRATCH"
probe "partial index named, no predicate"            ok  34056  "SELECT count(*) FROM p_part WHERE content @@ 'parity'" "$SCRATCH"
probe "partial index, rows outside its predicate"    ok  0      "SELECT count(*) FROM p_part WHERE content @@ 'parity' AND ts < TIMESTAMP '2005-12-01'" "$SCRATCH"
probe "partial index scanned when named (EXPLAIN)"   ok  "~Index: p_part " "EXPLAIN SELECT count(*) FROM p_part WHERE content @@ 'parity'" "$SCRATCH"
probe "partial index built before the load"          ok  34056 "
CREATE TABLE p_late (id BIGINT, ts TIMESTAMP, content VARCHAR);
CREATE INDEX p_late_part ON p_late USING inverted (id, content log_text, ts) WHERE ts >= TIMESTAMP '2005-12-01';
INSERT INTO p_late SELECT id, ts, content FROM p_ev;
VACUUM (REFRESH_TABLE) p_late;
SELECT count(*) FROM p_late_part WHERE content @@ 'parity';" "$SCRATCH"
probe "partial index, predicate matches no row"      ok  0 "
CREATE INDEX p_none ON p_ev USING inverted (id, content log_text, ts) WHERE ts >= TIMESTAMP '2026-01-01';
VACUUM (REFRESH_TABLE) p_ev;
SELECT count(*) FROM p_none WHERE content @@ 'parity';" "$SCRATCH"
probe "partial index follows an UPDATE into it"      ok  34057 "
CREATE TABLE p_upd AS SELECT * FROM p_ev;
CREATE INDEX p_upd_full ON p_upd USING inverted (id, content log_text, ts);
CREATE INDEX p_upd_part ON p_upd USING inverted (id, content log_text, ts) WHERE ts >= TIMESTAMP '2005-12-01';
VACUUM (REFRESH_TABLE) p_upd;
UPDATE p_upd SET ts = TIMESTAMP '2005-12-15 00:00:00'
 WHERE id = (SELECT min(id) FROM p_upd_full WHERE content @@ 'parity' AND ts < TIMESTAMP '2005-12-01');
VACUUM (REFRESH_TABLE) p_upd;
SELECT count(*) FROM p_upd_part WHERE content @@ 'parity';" "$SCRATCH"
# Pattern A (search table): the predicate is ignored, which is what the first probe measured.
probe "search table: partial index named"            ok  121498 "SELECT count(*) FROM p_search_part WHERE content @@ 'parity'" "$SCRATCH"
probe "search table: partial holds rows outside it"  ok  t      "SELECT count(*) > 0 FROM p_search_part WHERE content @@ 'parity' AND ts < TIMESTAMP '2005-12-01'" "$SCRATCH"
probe "search table: planner picks for table query"  ok  "~Index: p_search " "EXPLAIN SELECT count(*) FROM p_search WHERE content @@ 'parity' AND ts >= TIMESTAMP '2005-12-01'" "$SCRATCH"
info "search table: partial, rows outside (87,442 = complement)" "$(sql_in "$SCRATCH" <<<"SELECT count(*) FROM p_search_part WHERE content @@ 'parity' AND ts < TIMESTAMP '2005-12-01';")"
info "build: full index (4,747,963 rows), ms"         "$full_ms"
info "build: partial index (424,614 rows), ms"        "$part_ms"
info "query: partial named, median of 21, ms"          "$(median_ms "$SCRATCH" 21 "SELECT count(*) FROM p_part WHERE content @@ 'parity';")"
info "query: full + window, median of 21, ms"          "$(median_ms "$SCRATCH" 21 "SELECT count(*) FROM p_full WHERE content @@ 'parity' AND ts >= TIMESTAMP '2005-12-01';")"

echo; echo "############ 6. ANALYTICS (doc §2) ############"
probe "percentile_cont(0.95) WITHIN GROUP"           ok  0.38181753999999996 "SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_s) FROM os_ev WHERE latency_s IS NOT NULL"
probe "quantile_cont(col, 0.95)"                     ok  0.38181753999999996 "SELECT quantile_cont(latency_s, 0.95) FROM os_ev WHERE latency_s IS NOT NULL"
probe "date_bin"                                     ok  "" "SELECT date_bin(INTERVAL '1 hour', ts, TIMESTAMP '2005-01-01') FROM bgl_ev LIMIT 1"
probe "date_trunc on a TIMESTAMP column, no cast"    ok  "2005-06-03 00:00:00" "SELECT date_trunc('day', min(ts)) FROM bgl_ev"
probe "date_trunc('week', ts::timestamptz)"          ok  "" "SELECT date_trunc('week', ts::timestamptz) FROM bgl_ev LIMIT 1"
probe "generate_series"                              ok  10 "SELECT count(*) FROM generate_series(1, 10)"
probe "regr_slope"                                   ok  "" "SELECT regr_slope(latency_s, pid) FROM os_ev WHERE latency_s IS NOT NULL"
probe "GROUPING SETS"                                ok  "" "SELECT count(*) FROM (SELECT component, level, count(*) FROM bgl_ev GROUP BY GROUPING SETS ((component), (level))) t"
probe "GROUP BY ALL"                                 ok  "" "SELECT count(*) FROM (SELECT component, count(*) FROM bgl_ev GROUP BY ALL) t"
probe "LAG window"                                   ok  4747962 "SELECT count(l) FROM (SELECT LAG(ts) OVER (ORDER BY ts) AS l FROM bgl_ev) t"
probe "SUM() OVER (... ROWS UNBOUNDED PRECEDING)"      ok  "" "SELECT max(s) FROM (SELECT SUM(1) OVER (ORDER BY ts ROWS UNBOUNDED PRECEDING) AS s FROM os_ev) t"
probe "EXTRACT(epoch FROM ts)"                       ok  "" "SELECT extract(epoch FROM ts) FROM bgl_ev LIMIT 1"
probe "ts + INTERVAL '5 minutes'"                    ok  "" "SELECT ts + INTERVAL '5 minutes' FROM bgl_ev LIMIT 1"
probe "array literal [1,2,3]"                        ok  3 "SELECT count(*) FROM (SELECT unnest([1,2,3])) t"
probe "array literal ARRAY[1,2,3]"                   ok  3 "SELECT count(*) FROM (SELECT unnest(ARRAY[1,2,3])) t"
probe "integer division truncates (7/2)"             ok  3 "SELECT 7/2"

echo; echo "############ 7. INTROSPECTION / OPS (doc §2, §3 row 2) ############"
probe "sdb_indexes()"                                ok  "" "SELECT count(*) FROM sdb_indexes()"
probe "sdb_metrics columns (no size column)"         ok  "metric,value,description,relation_id" "SELECT string_agg(column_name, ',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_name = 'sdb_metrics'"
probe "pg_class.relpages for bgl_idx"                ok  0 "SELECT relpages FROM pg_class WHERE relname = 'bgl_idx'"
probe "sdb_functions()"                              ok  "" "SELECT count(*) FROM sdb_functions() WHERE function_name LIKE 'ts_%'"
probe "EXPLAIN ANALYZE on bgl_idx"                   ok  "" "EXPLAIN ANALYZE SELECT count(*) FROM bgl_idx WHERE content @@ 'parity'"
probe "inverted index over a read_parquet view"      ok  21212 "
DROP VIEW IF EXISTS p_os_v CASCADE;
CREATE VIEW p_os_v AS SELECT * FROM read_parquet('$DATA/openstack.parquet');
CREATE INDEX p_os_v_idx ON p_os_v USING inverted (message log_text);
SELECT count(*) FROM p_os_v_idx WHERE message @@ 'base';" "$SCRATCH"
probe "REINDEX INDEX on the view-backed index"       ok  21212 "REINDEX INDEX p_os_v_idx; SELECT count(*) FROM p_os_v_idx WHERE message @@ 'base';" "$SCRATCH"

echo; echo "############ 8. CLAIMED GOTCHAS (doc §4) ############"
probe "VARCHAR(10) accepted, stores 20 chars"        ok  20 "
DROP TABLE IF EXISTS probe_vc;
CREATE TABLE probe_vc (a VARCHAR(10));
INSERT INTO probe_vc VALUES ('12345678901234567890');
SELECT length(a) FROM probe_vc;" "$SCRATCH"
probe "to_timestamp(text)"                           err "" "SELECT to_timestamp('2005-06-03 15:42:50')"
probe "to_timestamp(epoch)"                          ok  "" "SELECT to_timestamp(1117838570)"
probe "strptime"                                     ok  "2005-06-03 15:42:50.363779" "SELECT strptime('2005-06-03-15.42.50.363779', '%Y-%m-%d-%H.%M.%S.%f')"
probe "to_char"                                      err "" "SELECT to_char(NOW(), 'YYYY-MM')"
probe "to_date"                                      err "" "SELECT to_date('2005-06-03')"
probe "regexp_extract"                               ok  41.81 "SELECT regexp_extract('Took 41.81 seconds', 'Took ([0-9.]+)', 1)"
probe "regexp_extract no match -> ''"                ok  "[]" "SELECT '[' || regexp_extract('abc', 'zz([0-9]+)', 1) || ']'"
probe "CREATE ROLE ... LOGIN PASSWORD"                 ok  "" "DROP ROLE IF EXISTS probe_login; CREATE ROLE probe_login LOGIN PASSWORD 'x'; DROP ROLE probe_login;"

echo; echo "############ 9. ROLE SCOPING (doc §6) ############"
sql_in "$SCRATCH" <<'SQL' >/dev/null
DROP VIEW IF EXISTS p_search_v;
DROP FUNCTION IF EXISTS p_count();
DROP ROLE IF EXISTS probe_reader;
CREATE ROLE probe_reader NOLOGIN;
CREATE VIEW p_search_v AS SELECT id, ts, content FROM p_full;
GRANT SELECT ON p_search_v TO probe_reader;
CREATE FUNCTION p_count() RETURNS BIGINT LANGUAGE sql SECURITY DEFINER AS $$ SELECT count(*) FROM p_ev $$;
GRANT EXECUTE ON FUNCTION p_count() TO probe_reader;
SQL
probe "GRANT SELECT on an index relation"            err "" "GRANT SELECT ON p_full TO probe_reader" "$SCRATCH"
probe "role: search through a view over the index"   ok  121498 "SET ROLE probe_reader; SELECT count(*) FROM p_search_v WHERE content @@ 'parity';" "$SCRATCH"
probe "role: base table without a grant"             err "" "SET ROLE probe_reader; SELECT count(*) FROM p_ev;" "$SCRATCH"
probe "role: index relation without a table grant"   err "" "SET ROLE probe_reader; SELECT count(*) FROM p_full WHERE content @@ 'parity';" "$SCRATCH"
probe "role: SECURITY DEFINER function honoured"     err "" "SET ROLE probe_reader; SELECT p_count();" "$SCRATCH"
sql_in "$SCRATCH" <<'SQL' >/dev/null
DROP VIEW IF EXISTS p_search_v;
DROP FUNCTION IF EXISTS p_count();
DROP ROLE IF EXISTS probe_reader;
SQL

# ------------------------------------------------------------------------------ cleanup
sql_in postgres <<<"DROP DATABASE IF EXISTS $SCRATCH;" >/dev/null

echo
echo "probe: $ROWS rows, $DRIFT drifted from docs/capabilities.md"
[[ $DRIFT -eq 0 ]]
