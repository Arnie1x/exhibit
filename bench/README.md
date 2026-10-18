# Huge-datasets bench

How much data we actually queried, how long it took, and on what machine: the question the
organisers' Q&A asks of the huge-datasets award (team plan §14, item 3). Everything below is
measured by `sql/70_bench.sql`; nothing is downloaded to disk, and only the indexes are local.

```bash
make bench                        # one 1-second slice, about 1.5 minutes
make bench-ladder                 # 1 and 10 seconds, each index sized on disk (bench/run_ladder.sh)
BENCH_LADDER="30" make bench-ladder   # reproduces the crash below; restart with `docker start serenedb`
```

**Machine:** Windows 11, Docker Desktop 29.7.2, 16 vCPU and 7.6 GB for the Docker VM, image
`serenedb/serenedb:26.09.1.3` (amd64, `sha256:018a3187c193…`). The remote file sits on S3 in
`eu-west-3`; the slowest read below moved 367.3 MiB in 57.5 s, so this box sees about 6 MiB/s, and
every remote time here is network-bound. Logs: `logs/bench-*.log` (gitignored; re-run to see them).

**Cost.** The file is read with anonymous HTTPS GETs from a public S3 bucket. Nothing is downloaded
to disk and no storage, egress or query fee is billed to us — the only cost is the machine the index
is built on, the Docker VM described above.

**The file:** `https://public-pme.s3.eu-west-3.amazonaws.com/text_bench/part_000.parquet`, the
organisers' OTel bench: **1,000,000,000 rows**, 1,624 row groups, 40,991,166,725 bytes, sorted by
time over 2025-09-23 00:00:00 → 00:29:24 (about 567,000 rows per second of log time).

## A. The whole file, from its footer

| Step | Time | Read |
| --- | --- | --- |
| rows, row groups, size, time span, compressed bytes per column | 1.4–3.3 s | the 4.8 MB footer only |
| `count(*)` over all 1,000,000,000 rows | 0.1–0.8 s | row-group metadata |

## B. A slice of the remote file, indexed in place

A view over `read_parquet(<url>)` with `WHERE "TimestampTime" >= t AND "TimestampTime" < t + N s`,
then `CREATE INDEX … USING inverted (body, service, ts, trace_id)` on the view: the documented
zero-ETL mechanism. All remote reads run with `enable_external_file_cache = false` (why: the last
section). Slices start at 2025-09-23 00:05:00.

| | 1 s | 10 s | 30 s | 60 s |
| --- | ---: | ---: | ---: | ---: |
| Row groups the slice touches (from statistics) | 2 | 10 | 27 | 52 |
| Rows in those row groups | 1,228,800 | 6,144,000 | 16,588,800 | 31,948,800 |
| Read `ServiceName` alone, cold: bytes in / time | 8.7 MiB / 12.9 s | 10.0 MiB / 13.3 s | 13.2 MiB / 16.8 s | 17.5 MiB / 14.3 s |
| Read `Body` alone, cold: bytes in / time | 99.8 MiB / 21.8 s | 142.7 MiB / 31.3 s | 233.8 MiB / 38.3 s | 367.3 MiB / 57.5 s |
| **Index build: rows / time** | **536,041 / 24.8–32.2 s** | **5,275,597 / 60.0 s** | **server crashed** | **server crashed** |
| Build rate | 16,648–21,596 rows/s | 87,898 rows/s | — | — |
| Index on disk | 14,676 KB | 136,472 KB | — | — |
| Phrase `failed to charge card` + facet by service | 28,520 hits, 8–18 ms | 290,473 hits, 13 ms | — | — |
| One trace id → its log lines (materialises `body` from S3) | 9 lines, 5 services, 8.2–12.8 s | 9 lines, 5 services, 36.7 s | — | — |
| `REINDEX INDEX` on the unchanged file | 1.0–1.1 s | 3.6 s | — | — |

For scale, the whole file holds `ServiceName` in 297 MB and `Body` in 9.07 GB (compressed).

Read it like this:

- **Pruning is what makes remote search possible.** One second of data read 8.7 MiB of a 297 MB
  column; sixty seconds read 17.5 MiB. Every cold read starts at about 13 s, because the reader
  fetches each row group's `TimestampTime` chunk (1,645 GETs) instead of using the footer statistics.
- **Search on the slice index never touches S3**: 13–18 ms for a phrase and a facet over millions of
  rows. Only a query that returns a column the index does not hold (here, the log text of a trace)
  goes back to the file, and pays the network for it.
- **The trace lookup is log-side trace context**: one request's lines across services, in time order
  (`payment` logs "Visa cache full", then `frontend` logs "failed to charge card"). There is no span
  data in this file, so it is not a logs-to-traces join.
- **Extrapolation, not a measurement:** at the 10-second build rate the whole file would take about
  3.2 hours on this connection (`make bench BENCH_SECONDS=10` prints it; the 1-second default prints
  about 13 hours, because the fixed ~13 s of GETs dominates a small slice), and the 30-second crash
  says it would have to be built in slices, one index per slice or a glob over smaller files.

## C. The same mechanism at full size, on local Parquet

An index on `CREATE VIEW bench_bgl AS SELECT * FROM read_parquet('/data/loghub/bgl.parquet')`
(4,747,963 rows), against an index with the same four columns on the derived table `bgl_ev`. Four
runs (every bench run ends with C).

| | Index on the Parquet view | Index on `bgl_ev` |
| --- | --- | --- |
| Build (4 columns, 4,747,963 rows) | 0.69 / 1.25 / 1.16 / 1.17 s | 1.07 / 1.62 / 1.68 / 1.99 s (with `VACUUM (REFRESH_TABLE)`) |
| `content @@ ts_phrase('data TLB error interrupt')` | 152,734 | 152,734 (and `bgl_idx`: 152,734) |
| `content @@ 'ciod'` | 350,567 | `bgl_idx`: 350,567 |
| Phrase + facet by component | 12–17 ms | 10–22 ms |
| `REINDEX INDEX`, file unchanged | 17–50 ms | — |

The view index answers exactly what the table indexes answer, builds faster (there is no table to
refresh), and still returns columns it does not hold (`date`, `timestamp`) by reading them from the
file by row number.

## What did not work, and why it is still on this page

On 26.09.1.3 the remote path has one setting that decides everything (`docs/capabilities.md` §11):

- with `enable_external_file_cache` **on** (the default), a time-filtered read is **not** pruned: a
  count over one second of data pulled 600+ MB in 5 minutes, and big reads end in a server crash
  (`SIGSEGV`, the same program counter every time, exit 139; the data volume survives a restart);
- every read that included `SeverityText` crashed it too, so the severity columns stay out of the
  remote index;
- with the cache off, the 30-second and 60-second builds (16.6M and 31.9M rows in their row groups)
  crashed the same way, during `CREATE INDEX`. The ceiling on this box lies between 10 seconds of
  data (5,275,597 rows, works) and 30 seconds (crashes), which is why the default ladder stops at 10.

A team that measured and reported "this did not pay off" is more useful to the next team than one
that claims a number it cannot show, so the crashes are here, with their reproduction.
