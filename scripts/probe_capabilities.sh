#!/bin/bash
# Capability probe: test the load-bearing claims in the teammate's plan against the
# real engine (26.09.1.3), plus the architecture-critical @@ question.
PSQL="psql -h 127.0.0.1 -p 7890 -U postgres -q -tA -c"
PASS=0; FAIL=0

probe() {  # label, sql
  if out=$(psql -h 127.0.0.1 -p 7890 -U postgres -q -tA -c "$2" 2>&1); then
    printf 'PASS  %-46s %s\n' "$1" "$(echo "$out" | head -1 | cut -c1-34)"
    PASS=$((PASS+1))
  else
    printf 'FAIL  %-46s %s\n' "$1" "$(echo "$out" | head -1 | cut -c1-96)"
    FAIL=$((FAIL+1))
  fi
}

echo "############ SEARCH / TEXT ANALYSIS ############"
probe "ts_dict_agg (facets)"          "SELECT unnest(ts_dict_agg(content)) FROM bgl LIMIT 1"
probe "ts_dict_count"                 "SELECT unnest(ts_dict_count(content)) FROM bgl LIMIT 1"
probe "ts_offsets"                    "SELECT ts_offsets(content) FROM bgl LIMIT 1"
probe "ts_highlight"                  "SELECT ts_highlight(content, ts_offsets(content)) FROM bgl LIMIT 1"
probe "BM25(tableoid)"                "SELECT BM25(bgl.tableoid) FROM bgl WHERE content @@ 'parity' LIMIT 1"
probe "BM25() no-arg in ORDER BY"     "SELECT id FROM bgl WHERE content @@ 'parity' ORDER BY BM25() DESC LIMIT 1"
probe "ts_any([...]) array form"      "SELECT count(*) FROM bgl WHERE content @@ ts_any(['data','storage'])"
probe "ts_all([...]) array form"      "SELECT count(*) FROM bgl WHERE content @@ ts_all(['data','storage'])"
probe "ts_phrase (verified earlier)"  "SELECT count(*) FROM bgl WHERE content @@ ts_phrase('data TLB error interrupt')"
probe "ts_levenshtein"                "SELECT count(*) FROM bgl WHERE content @@ ts_levenshtein('parity', 1)"
probe "ts_starts_with"                "SELECT count(*) FROM bgl WHERE content @@ ts_starts_with('instr')"
probe "ts_regexp"                     "SELECT count(*) FROM bgl WHERE content @@ ts_regexp('instru.*')"
probe "to_tsquery (Lucene)"           "SELECT count(*) FROM bgl WHERE content @@ to_tsquery('data AND TLB')"
probe "websearch_to_tsquery"          "SELECT count(*) FROM bgl WHERE content @@ websearch_to_tsquery('data TLB')"
probe "ts_lexize on 'en'"             "SELECT ts_lexize('en', 'R02-M1-N0-C:J12-U11 ciod: failed')"
probe "dict syntax: AS split_text()"  "CREATE TEXT SEARCH DICTIONARY probe_a AS split_text(case := 'lower') WITH (frequency, position, offset)"
probe "dict syntax: template= (ours)" "CREATE TEXT SEARCH DICTIONARY probe_b (template='split_by_non_alpha', case='lower', frequency=true, norm=true, position=true)"

echo
echo "############ ANALYTICS ############"
probe "percentile_cont WITHIN GROUP"  "SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_s) FROM openstack WHERE latency_s IS NOT NULL"
probe "quantile_cont(col, q)"         "SELECT quantile_cont(latency_s, 0.95) FROM openstack WHERE latency_s IS NOT NULL"
probe "date_bin"                      "SELECT date_bin(INTERVAL '1 hour', ts, TIMESTAMP '2005-01-01') FROM bgl LIMIT 1"
probe "date_trunc week"               "SELECT date_trunc('week', ts) FROM bgl LIMIT 1"
probe "generate_series"               "SELECT count(*) FROM generate_series(1, 10)"
probe "regr_slope"                    "SELECT regr_slope(latency_s, pid) FROM openstack WHERE latency_s IS NOT NULL"
probe "GROUPING SETS"                 "SELECT component, level, count(*) FROM bgl GROUP BY GROUPING SETS ((component),(level)) LIMIT 1"
probe "GROUP BY ALL"                  "SELECT component, count(*) FROM bgl GROUP BY ALL LIMIT 1"
probe "LAG window"                    "SELECT LAG(ts) OVER (ORDER BY ts) FROM bgl LIMIT 1"
probe "SUM() OVER ROWS UNBOUNDED"     "SELECT SUM(1) OVER (ORDER BY ts ROWS UNBOUNDED PRECEDING) FROM bgl LIMIT 1"
probe "EXTRACT(epoch FROM ts)"        "SELECT extract(epoch FROM ts) FROM bgl LIMIT 1"
probe "ts + INTERVAL '5 minutes'"     "SELECT ts + INTERVAL '5 minutes' FROM bgl LIMIT 1"
probe "array literal [1,2,3]"         "SELECT unnest([1,2,3])"
probe "array literal ARRAY[1,2,3]"    "SELECT unnest(ARRAY[1,2,3])"

echo
echo "############ INTROSPECTION / OPS ############"
probe "sdb_indexes()"                 "SELECT * FROM sdb_indexes() LIMIT 1"
probe "sdb_metrics"                   "SELECT * FROM sdb_metrics LIMIT 1"
probe "sdb_functions()"               "SELECT function_name FROM sdb_functions() WHERE function_name LIKE 'ts_%' LIMIT 3"
probe "EXPLAIN ANALYZE"               "EXPLAIN ANALYZE SELECT count(*) FROM bgl WHERE content @@ 'parity'"

echo
echo "############ CLAIMED GOTCHAS ############"
probe "VARCHAR(n) -- claimed to fail"  "CREATE TABLE probe_vc (a VARCHAR(10))"
probe "to_timestamp(text) -- claimed fail" "SELECT to_timestamp('2005-06-03 15:42:50')"
probe "strptime"                       "SELECT strptime('2005-06-03-15.42.50.363779', '%Y-%m-%d-%H.%M.%S.%f')"
probe "to_char -- claimed to fail"     "SELECT to_char(NOW(), 'YYYY-MM')"
probe "to_date -- claimed to fail"     "SELECT to_date('2005-06-03')"
probe "regexp_extract"                 "SELECT regexp_extract('Took 41.81 seconds', 'Took ([0-9.]+)', 1)"
probe "regexp_extract no-match -> ''"  "SELECT '[' || regexp_extract('abc', 'zz([0-9]+)', 1) || ']'"
probe "CREATE ROLE ... LOGIN PASSWORD" "CREATE ROLE probe_login LOGIN PASSWORD 'x'"
