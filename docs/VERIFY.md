# Independent verification: new figures in `docs/slides.md`

- **Date:** 18 Oct 2026
- **Target:** `docs/slides.md`, slides 10, 11 and 12 (repo at `dc59a95`)
- **Scope:** only the figures added since the 17 Oct independent check:
  1. slide 10: weekly incident bars for the Lustre and ciod-socket signatures (5-minute gap,
     signature × midplane, week = `date_trunc('week', incident start)`);
  2. slide 11: DTLB nodes and active days, and 348,460 alert lines / 19,250 incidents = 18.1;
  3. slide 12: median spawn time over the instances that have one, and the five slowest instances.
- **Engine:** `PostgreSQL 18.3 (SereneDB 26.09.1.3)`, Docker container `serenedb`, freshly
  bootstrapped on 18 Oct. Read-only: SELECT statements only, through
  `docker exec -i serenedb psql -h 127.0.0.1 -p 7890 -U postgres`. `statement_timeout` was set,
  but this engine does not enforce it (it only warns).

## Method

**Layer 1, reproducibility.** Each figure is printed by `make demo` (`sql/90_queries.sql`): W1 L4 and
L4b (item 1), W1 M1 and M2 (item 2), W2 L1 and L2 (item 3). It is present in the stored run
`logs/v2-demo2.log`. A fresh run of `sql/90_queries.sql` today printed sections L4 to M2 and W2 L1 to L2
exactly as the stored log does (`diff` was empty).

**Layer 2, correctness.** New SQL written from the wording of each claim. None of it reads
`bgl_sig`, `bgl_episode`, `bgl_incident`, `bgl_signature_stats`, `bgl_episode_sensitivity`,
`mgr_bgl_risk`, `os_sig` or `os_instance_durations`. What was reused, and why:

- `bgl_ev` (the derived table: `ts`, `node`, `midplane`, `alert_category`, `content`) and `os_ev`
  (`content`, plus `instance_id` used only as a cross-check).
- The signature mask (UUID → `{uuid}`, then digit runs → `{n}`), copied from `sql/30_views.sql`. A
  signature is a definition, not a computed result, so it has to match the definition.

What differs from the stored queries:

- Alert lines are `alert_category <> '-'`, not `is_alert`. The two give the same 348,460 rows, and no
  alert line has a NULL label.
- Episodes are counted as episode **starts**: rows whose previous timestamp in the same
  (signature, midplane) is missing or more than 300,000,000 µs earlier, measured with `epoch_us`
  integer arithmetic. The stored queries compare against an `INTERVAL`, number episodes with a
  `SUM() OVER` window and then group by episode. Here an incident's start is the timestamp of its
  start row.
- Weeks are bucketed twice: once with `date_trunc('week', …)`, once with plain date arithmetic from
  Monday 2005-05-30, without `date_trunc`.
- "Last 9 weeks" is anchored on `max(ts)` over **all** BGL lines (the corpus), not over the
  incidents.
- OpenStack spawn time and instance ID are parsed from the message text
  (`Took N seconds to spawn the instance on the hypervisor`, `[instance: <uuid>]`), not taken from
  `os_ev.spawn_s`. The median is computed three ways: `percentile_cont(0.5) WITHIN GROUP` (linear
  interpolation), `median()`, and the average of the two middle rows by `row_number`.

## Results

24 claims: **24 match, 0 mismatch, 0 unverifiable.**

| # | Claim | Slide | Evidence (`make demo`) | Stated | Independent | Independent SQL | Operator | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | Lustre `Lustre mount FAILED : bglio{n} : point /p/gb{n}`, incidents with start in week of 2005-08-29 | 10 | W1 L4b | 1,872 | 1,872 | V1b, V1d | episode starts, LAG over (sig, midplane), gap > 300 s (µs integers); `date_trunc('week')` and date arithmetic | match |
| 2 | Lustre, week of 2005-09-05 | 10 | W1 L4b | 1,244 | 1,244 | V1b, V1d | same | match |
| 3 | Lustre, week of 2005-09-12 | 10 | W1 L4b | 551 | 551 | V1b, V1d | same | match |
| 4 | Lustre total, no incidents in any other week | 10 | W1 L4, L4b | 3,667; 3 active weeks | 3,667; exactly 3 weeks with incidents | V1a, V1b (ROLLUP) | same | match |
| 5 | ciod-socket signature, week of 2005-11-14 | 10 | W1 L4b | 213 | 213 | V1b, V1d | same | match |
| 6 | ciod-socket, week of 2005-11-21 | 10 | W1 L4b | 1,110 | 1,110 | V1b, V1d | same | match |
| 7 | ciod-socket, week of 2005-11-28 | 10 | W1 L4b | 789 | 789 | V1b, V1d | same | match |
| 8 | ciod-socket, week of 2005-12-05 | 10 | W1 L4b | 136 | 136 | V1b, V1d | same | match |
| 9 | ciod-socket, week of 2005-12-12 | 10 | W1 L4b | 900 | 900 | V1b, V1d | same | match |
| 10 | ciod-socket, week of 2005-12-19 | 10 | W1 L4b | 186 | 186 | V1b, V1d | same | match |
| 11 | ciod-socket, week of 2005-12-26 | 10 | W1 L4b | 286 | 286 | V1b, V1d | same | match |
| 12 | ciod-socket, week of 2006-01-02 | 10 | W1 L4b | 18 | 18 | V1b, V1d | same | match |
| 13 | ciod-socket total, none in other weeks | 10 | W1 L4, L4b | 3,638; 8 active weeks | 3,638; exactly 8 weeks with incidents | V1a, V1b (ROLLUP) | same | match |
| 14 | ciod-socket: all incidents in the last 9 weeks of the corpus | 10 | W1 L4 (`last_9_weeks` 3,638) | 3,638 of 3,638 | 3,638 of 3,638. Last corpus week 2006-01-02, window from 2005-11-07; first start 2005-11-17 05:33, last 2006-01-03 11:56 | V1c | same, anchor = `date_trunc('week', max(ts))` over all of `bgl_ev` | match |
| 15 | Exact masked text of the two top signatures by incidents | 10 | W1 L2, L4 | `ciod: Error reading message prefix on CioStream socket to {n}.{n}.{n}.{n}:{n}, Link has been severed` (and the Lustre text) | identical, 100 characters; ranked 1st (Lustre 3,667) and 2nd (ciod 3,638) by recomputed incidents | V1a | equality on the masked signature | match |
| 16 | DTLB (`KERNDTLB`, `data TLB error interrupt`): distinct nodes | 11 | W1 M2 (`nodes_affected`) | 541 | 541 (same by signature, by category and by both) | V2b | `count(DISTINCT node)` over alert lines | match |
| 17 | DTLB active days (distinct calendar days with its alert lines) | 11 | W1 M2 (`active_days`) | 11 | 11 (2005-06-05 to 2005-11-28, listed in V2c) | V2b, V2c | `count(DISTINCT date_trunc('day', ts))` | match |
| 18 | Alert lines | 11 | W1 M1 | 348,460 | 348,460 | V2a | `count(*)` where `alert_category <> '-'` | match |
| 19 | Incidents, 5-minute gap, signature × midplane | 11 | W1 M1 | 19,250 | 19,250 | V2a | episode starts, gap > 300,000,000 µs | match |
| 20 | Lines per incident | 11 | W1 M1 | 18.1 | 18.1 (unrounded 18.10181818…) | V2a | `count(*)::DOUBLE / incidents`, `round(…, 1)` | match |
| 21 | Median spawn time | 12 | W2 L2 (`quantile_cont`, linear) | 19.74 s | 19.74 s by all three methods. Both middle values are 19.74, so the interpolation method cannot change the result | V3b | `percentile_cont(0.5)` (linear), `median()`, middle-two average | match |
| 22 | Instances that have a spawn time | 12 | W2 L2 (`spawned`) | 2,066 | 2,066 (2,066 spawn lines, 1 per instance; text ID = parser ID on all 2,066) | V3a, V3b | `count(DISTINCT iid)` over parsed spawn lines | match |
| 23 | 5th slowest by spawn time | 12 | W2 L1 | d7d68893-… 26.69 s | d7d68893-c44f-4e7c-8d4b-0e7801d62776, 26.69 s, no tie (6th is 22.56 s) | V3c | `rank()` over per-instance `max(spawn)` descending | match |
| 24 | Positions 1 to 4 | 12 | W2 L1 | a445709b 50.72, 544fd51c 41.81, 1643649d 31.27, ae651dff 29.46 | a445709b 50.72, 544fd51c 41.81, 1643649d 31.27, ae651dff 29.46 | V3c | same | match |

No full-text operator applies to any claim in scope: they are episode counts, distinct counts and a
percentile, all computed on the derived tables. No count was checked with `LIKE`.

### Notes

- 271 alert lines have `midplane = 'UNKNOWN'` (192 KERNPOW, 37 MASABNORM, 32 KERNSERV, 10 MASNORM).
  Both sides treat them as one failure domain per signature. They do not touch the Lustre, ciod or
  DTLB figures, and they are inside the 19,250 on both sides.
- The two week bucketings agree: `date_trunc('week')` here starts weeks on Monday (2005-08-29 is a
  Monday), the same as the date-arithmetic weeks counted from 2005-05-30.
- Ties in time inside a partition give a zero gap. So the count of episode starts does not depend
  on how tied rows are ordered, and the one-row-per-instance spawn data has no ties at rank 5.

## Independent SQL

### V1a: top signatures by recomputed incidents (exact masked text)

```sql
WITH a AS (
  SELECT midplane, epoch_us(ts) AS t_us,
         regexp_replace(
           regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig
  FROM bgl_ev
  WHERE alert_category <> '-'
), g AS (
  SELECT sig, t_us - lag(t_us) OVER (PARTITION BY sig, midplane ORDER BY t_us) AS gap_us
  FROM a
)
SELECT sig, length(sig) AS len, count(*) AS lines,
       sum(CASE WHEN gap_us IS NULL OR gap_us > 300000000 THEN 1 ELSE 0 END) AS incidents
FROM g
GROUP BY sig
ORDER BY incidents DESC
LIMIT 5;
-- Lustre mount FAILED : bglio{n} : point /p/gb{n}                                        | 47  | 26426 | 3667
-- ciod: Error reading message prefix on CioStream socket to {n}.{n}.{n}.{n}:{n}, Link has been severed | 100 | 26546 | 3638
```

### V1b: weekly incident starts for the two signatures, every week that has any

```sql
WITH a AS (
  SELECT ts, midplane, epoch_us(ts) AS t_us,
         regexp_replace(
           regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig
  FROM bgl_ev
  WHERE alert_category <> '-'
), s AS (
  SELECT * FROM a
  WHERE sig IN ('Lustre mount FAILED : bglio{n} : point /p/gb{n}',
                'ciod: Error reading message prefix on CioStream socket to {n}.{n}.{n}.{n}:{n}, Link has been severed')
), g AS (
  SELECT sig, ts, t_us - lag(t_us) OVER (PARTITION BY sig, midplane ORDER BY t_us) AS gap_us
  FROM s
), starts AS (
  SELECT sig, ts FROM g WHERE gap_us IS NULL OR gap_us > 300000000
)
SELECT left(sig, 12) AS sig, date_trunc('week', ts)::date AS week_of, count(*) AS incidents
FROM starts
GROUP BY ROLLUP (left(sig, 12), date_trunc('week', ts)::date)
ORDER BY 1 NULLS LAST, 2 NULLS LAST;
-- Lustre: 2005-08-29 1872 | 2005-09-05 1244 | 2005-09-12 551 | total 3667
-- ciod:   2005-11-14 213 | 11-21 1110 | 11-28 789 | 12-05 136 | 12-12 900 | 12-19 186 | 12-26 286 | 2006-01-02 18 | total 3638
```

### V1c: ciod in the last 9 weeks, anchored on the corpus's last timestamp

```sql
WITH a AS (
  SELECT ts, midplane, epoch_us(ts) AS t_us,
         regexp_replace(
           regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig
  FROM bgl_ev
  WHERE alert_category <> '-'
), g AS (
  SELECT sig, ts, t_us - lag(t_us) OVER (PARTITION BY sig, midplane ORDER BY t_us) AS gap_us
  FROM a
  WHERE sig = 'ciod: Error reading message prefix on CioStream socket to {n}.{n}.{n}.{n}:{n}, Link has been severed'
), lastw AS (
  SELECT date_trunc('week', max(ts)) AS w FROM bgl_ev
)
SELECT (SELECT w FROM lastw)::date AS corpus_last_week,
       ((SELECT w FROM lastw) - INTERVAL '56 days')::date AS ninth_week_back,
       count(*) AS incidents_total,
       count(*) FILTER (WHERE date_trunc('week', ts) >= (SELECT w FROM lastw) - INTERVAL '56 days') AS in_last_9_weeks,
       min(ts) AS first_incident_start, max(ts) AS last_incident_start
FROM g WHERE gap_us IS NULL OR gap_us > 300000000;
-- 2006-01-02 | 2005-11-07 | 3638 | 3638 | 2005-11-17 05:33:24.623263 | 2006-01-03 11:56:38.877831
```

### V1d: week buckets without `date_trunc`

```sql
-- same CTEs a and g as V1b, restricted to the two signatures, then:
SELECT left(sig, 5) AS sig,
       (DATE '2005-05-30' + 7 * CAST(floor((ts::date - DATE '2005-05-30') / 7.0) AS INTEGER)) AS week_of,
       count(*) AS incidents
FROM g WHERE gap_us IS NULL OR gap_us > 300000000
GROUP BY 1, 2 ORDER BY 1, 2;
-- the same 11 (week, count) pairs as V1b
```

### V2a: alert lines, incidents and lines per incident

```sql
WITH a AS (
  SELECT midplane, epoch_us(ts) AS t_us,
         regexp_replace(
           regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig
  FROM bgl_ev
  WHERE alert_category <> '-'
), g AS (
  SELECT sig, t_us - lag(t_us) OVER (PARTITION BY sig, midplane ORDER BY t_us) AS gap_us
  FROM a
)
SELECT count(*) AS alert_lines,
       sum(CASE WHEN gap_us IS NULL OR gap_us > 300000000 THEN 1 ELSE 0 END) AS incidents_5min,
       round(count(*)::DOUBLE / sum(CASE WHEN gap_us IS NULL OR gap_us > 300000000 THEN 1 ELSE 0 END), 1) AS lines_per_incident,
       count(*)::DOUBLE / sum(CASE WHEN gap_us IS NULL OR gap_us > 300000000 THEN 1 ELSE 0 END) AS ratio_unrounded
FROM g;
-- 348460 | 19250 | 18.1 | 18.10181818181818
```

### V2b: DTLB distinct nodes and active days

```sql
WITH a AS (
  SELECT ts, node, alert_category,
         regexp_replace(
           regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig
  FROM bgl_ev
  WHERE alert_category <> '-'
)
SELECT 'signature = data TLB error interrupt' AS cut,
       count(*) AS alert_lines, count(DISTINCT node) AS nodes,
       count(DISTINCT date_trunc('day', ts)) AS active_days,
       min(ts)::date AS first_day, max(ts)::date AS last_day
FROM a WHERE sig = 'data TLB error interrupt'
UNION ALL
SELECT 'alert_category = KERNDTLB',
       count(*), count(DISTINCT node), count(DISTINCT date_trunc('day', ts)), min(ts)::date, max(ts)::date
FROM a WHERE alert_category = 'KERNDTLB'
UNION ALL
SELECT 'KERNDTLB AND signature',
       count(*), count(DISTINCT node), count(DISTINCT date_trunc('day', ts)), min(ts)::date, max(ts)::date
FROM a WHERE alert_category = 'KERNDTLB' AND sig = 'data TLB error interrupt';
-- all three cuts: 152734 lines | 541 nodes | 11 days | 2005-06-05 .. 2005-11-28
```

### V2c: the 11 DTLB days

```sql
SELECT date_trunc('day', ts)::date AS day, count(*) AS lines, count(DISTINCT node) AS nodes
FROM bgl_ev
WHERE alert_category = 'KERNDTLB'
GROUP BY 1 ORDER BY 1;
-- 2005-06-05 477/466, 06-11 152182/1, 07-15 1/1, 07-18 30/30, 08-15 1/1, 08-16 8/8,
-- 08-17 15/15, 08-18 5/5, 08-23 4/4, 11-24 1/1, 11-28 10/10  (11 rows)
```

### V3a: spawn lines, and the instance ID from the text against the parser's column

```sql
WITH l AS (
  SELECT instance_id AS parser_iid,
         nullif(regexp_extract(content, '\[instance: ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]', 1), '') AS text_iid,
         TRY_CAST(nullif(regexp_extract(content, 'Took ([0-9]+\.[0-9]+) seconds to spawn the instance on the hypervisor', 1), '') AS DOUBLE) AS sp
  FROM os_ev
)
SELECT count(*) FILTER (WHERE sp IS NOT NULL) AS spawn_lines,
       count(DISTINCT text_iid) FILTER (WHERE sp IS NOT NULL) AS instances_text_id,
       count(DISTINCT parser_iid) FILTER (WHERE sp IS NOT NULL AND parser_iid <> 'NONE') AS instances_parser_id,
       count(*) FILTER (WHERE sp IS NOT NULL AND (text_iid IS NULL OR text_iid <> parser_iid)) AS id_disagreements
FROM l;
-- 2066 | 2066 | 2066 | 0
```

### V3b: median spawn time, three ways

```sql
WITH l AS (
  SELECT nullif(regexp_extract(content, '\[instance: ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]', 1), '') AS iid,
         TRY_CAST(nullif(regexp_extract(content, 'Took ([0-9]+\.[0-9]+) seconds to spawn the instance on the hypervisor', 1), '') AS DOUBLE) AS sp
  FROM os_ev
), per AS (
  SELECT iid, max(sp) AS spawn_s, count(*) AS spawn_lines
  FROM l WHERE sp IS NOT NULL AND iid IS NOT NULL
  GROUP BY iid
), ranked AS (
  SELECT spawn_s, row_number() OVER (ORDER BY spawn_s) AS rn, count(*) OVER () AS n FROM per
)
SELECT (SELECT count(*) FROM per) AS instances_with_spawn,
       (SELECT max(spawn_lines) FROM per) AS max_spawn_lines_per_instance,
       (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY spawn_s) FROM per) AS median_percentile_cont,
       (SELECT median(spawn_s) FROM per) AS median_fn,
       (SELECT avg(spawn_s) FROM ranked WHERE rn IN ((n + 1) / 2, n / 2 + 1)) AS median_middle_two_avg,
       (SELECT string_agg(spawn_s::VARCHAR, ' , ' ORDER BY rn) FROM ranked WHERE rn IN ((n + 1) / 2, n / 2 + 1)) AS middle_values;
-- 2066 | 1 | 19.74 | 19.74 | 19.74 | 19.74 , 19.74
```

### V3c: the slowest seven, with ties shown

```sql
-- same CTEs l and per as V3b, then:
SELECT rank() OVER (ORDER BY spawn_s DESC) AS rank_desc, iid, spawn_s
FROM per ORDER BY spawn_s DESC, iid LIMIT 7;
-- 1 a445709b-6ad0-40ec-8860-bec60b6ca0c2 50.72
-- 2 544fd51c-4edc-4780-baae-ba1d80a0acfc 41.81
-- 3 1643649d-2f42-4303-bfcd-7798baec19f9 31.27
-- 4 ae651dff-c7ad-43d6-ac96-bbcd820ccca8 29.46
-- 5 d7d68893-c44f-4e7c-8d4b-0e7801d62776 26.69
-- 6 f0ff0b46-b3cd-43e6-97eb-839fd1cdaa87 22.56
-- 7 35ef7d14-fd25-42fd-8140-9b7f71416c6d 22.17
```
