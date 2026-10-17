#!/usr/bin/env bash
# The scale ladder for sql/70_bench.sql: one run per remote slice length, each index sized on disk.
#
# SereneDB reports no index size anywhere (sdb_metrics, sdb_indexes() and relpages all come up
# empty -- docs/capabilities.md), so size is measured where the postings live: the engine keeps one
# directory per indexed relation under <data dir>/engine_search/<db>/<schema>/<relation oid>, and
# for a view with one index on it, that directory IS the index. Needs the container (docker exec).
#
#   make bench-ladder                         # 1 and 10 seconds
#   BENCH_LADDER="30" make bench-ladder       # any list; 30 and 60 crash 26.09.1.3 here (bench/README.md)
set -euo pipefail

PSQL=${PSQL:-psql -h 127.0.0.1 -p 7890 -U postgres -P pager=off}
CONTAINER=${CONTAINER:-serenedb}
LADDER=${BENCH_LADDER:-1 10}
cd "$(dirname "$0")/.."
mkdir -p logs

size_kb() {   # $1 = relation name of the view the index is built on
    local oid dir
    oid=$($PSQL -tAc "SELECT oid FROM pg_class WHERE relname = '$1'" | tr -d '[:space:]')
    [ -n "$oid" ] || { echo "?"; return; }
    dir=$(docker exec "$CONTAINER" find /var/lib/serenedb/engine_search -mindepth 3 -maxdepth 3 \
          -type d -name "$oid" | head -1 | tr -d '\r')
    [ -n "$dir" ] || { echo "?"; return; }
    docker exec "$CONTAINER" du -sk "$dir" | cut -f1
}

printf '%-8s %-12s %-10s %-10s %-14s %s\n' slice rows build_s rows/s index_kb log
for s in $LADDER; do
    log="logs/bench-${s}s.log"
    $PSQL -v seconds="$s" -v keep=1 < sql/70_bench.sql > "$log" 2>&1 \
        || { echo "slice ${s}s FAILED, see $log"; exit 1; }
    # the summary row of the remote build, as psql aligns it: step | rows | seconds | rows/s | note
    row=$(grep 'B3 build' "$log" | tail -1 | tr -s ' ')
    rows=$(echo "$row" | cut -d'|' -f2 | tr -d ' ')
    secs=$(echo "$row" | cut -d'|' -f3 | tr -d ' ')
    rate=$(echo "$row" | cut -d'|' -f4 | tr -d ' ')
    printf '%-8s %-12s %-10s %-10s %-14s %s\n' "${s}s" "$rows" "$secs" "$rate" \
        "$(size_kb bench_otel_slice)" "$log"
done
echo "local view index over bgl.parquet (4,747,963 rows): $(size_kb bench_bgl) KB"

$PSQL -c "DROP INDEX IF EXISTS bench_otel_idx" -c "DROP VIEW IF EXISTS bench_otel_slice" \
      -c "DROP INDEX IF EXISTS bench_bgl_idx" -c "DROP VIEW IF EXISTS bench_bgl" \
      -c "DROP TEXT SEARCH DICTIONARY IF EXISTS bench_text" > /dev/null
echo "bench objects dropped"
