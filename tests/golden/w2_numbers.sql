-- tests/golden/w2_numbers.sql
-- Independent recomputation of the OpenStack (W2) numbers (sql-verifier, 17 Oct 2026).
-- Written fresh: it does not use os_sig, os_episode, os_incident, os_problem_incidents,
-- os_instance_durations, os_latency_by_file, any mgr_/lead_ view, sql/30_views.sql or
-- sql/99_smoke.sql. Read-only: SELECTs only, no DDL, no writes.
-- Primary source is the raw Parquet (checks the derive step); os_ev is a second source where useful.
--
-- Run (Windows host, no host psql):
--   export MSYS_NO_PATHCONV=1
--   docker exec -i serenedb psql -h 127.0.0.1 -p 7890 -U postgres -P pager=off -f - < tests/golden/w2_numbers.sql
--
-- Operators: exact equality on level / logger / message, regexp_matches and regexp_extract only to
-- recognise or extract fixed message shapes, LAG / ROWS-frame windows, quantile_cont and
-- percentile_cont (linear interpolation). No full-text (@@) and no LIKE/ILIKE anywhere.
-- Timestamps: the Parquet "timestamp" is VARCHAR and is cast with ::timestamp; gaps are taken on
-- extract(epoch ...) so they come out as DOUBLE seconds.

\set ON_ERROR_STOP on
SET statement_timeout = '120s';  -- accepted but NOT enforced by serened 26.09.1.3 (it warns)

-- ---------------------------------------------------------------------------------------------
-- W1. Level distribution.   expected INFO 204506, WARNING 3118, ERROR 186, CRITICAL 2; total 207812
-- ---------------------------------------------------------------------------------------------
WITH s(level, stated) AS (VALUES ('INFO', 204506), ('WARNING', 3118), ('ERROR', 186), ('CRITICAL', 2)),
raw AS (SELECT level, count(*) AS n FROM read_parquet('/data/loghub/openstack.parquet') GROUP BY level),
ev  AS (SELECT level, count(*) AS n FROM os_ev GROUP BY level)
SELECT 'W1 level ' || s.level AS claim, s.stated, raw.n AS independent_parquet, ev.n AS independent_os_ev,
       raw.n = s.stated AND ev.n = s.stated AS match
FROM s LEFT JOIN raw USING (level) LEFT JOIN ev USING (level)
UNION ALL
SELECT 'W1 total rows', 207812, (SELECT count(*) FROM read_parquet('/data/loghub/openstack.parquet')),
       (SELECT count(*) FROM os_ev),
       (SELECT count(*) FROM read_parquet('/data/loghub/openstack.parquet')) = 207812 AND (SELECT count(*) FROM os_ev) = 207812;

-- ---------------------------------------------------------------------------------------------
-- W2. ERROR lines from oslo_service.periodic_task = 8 tracebacks.
--   traceback = all ERROR periodic_task lines sharing (file, pid, timestamp)
--   expected: 184 lines, 8 groups, 23 lines each, 8 exact 'Traceback (most recent call last):'
--   lines, 1 exact header 'Error during ComputeManager._run_image_cache_manager_pass' per group,
--   1 line starting 'InvalidDiskInfo: ' per group (plus the 'raise exception.InvalidDiskInfo' frame),
--   minimum gap between consecutive tracebacks >= 300 s (measured 3524.885 s = 58m44.885s).
-- ---------------------------------------------------------------------------------------------
WITH e AS (SELECT origin_file, pid, "timestamp"::timestamp AS t, message
           FROM read_parquet('/data/loghub/openstack.parquet')
           WHERE level = 'ERROR' AND logger = 'oslo_service.periodic_task'),
tb AS (SELECT origin_file, pid, t, count(*) AS n,
              count(*) FILTER (WHERE message = 'Traceback (most recent call last):') AS n_tb,
              count(*) FILTER (WHERE message = 'Error during ComputeManager._run_image_cache_manager_pass') AS n_hdr,
              count(*) FILTER (WHERE regexp_matches(message, '^InvalidDiskInfo: ')) AS n_exc
       FROM e GROUP BY origin_file, pid, t),
g AS (SELECT extract(epoch FROM t) - extract(epoch FROM lag(t) OVER (ORDER BY t)) AS gap_s FROM tb)
SELECT 'W2 ERROR lines, periodic_task' AS claim, '184' AS stated, (SELECT sum(n) FROM tb)::VARCHAR AS independent,
       (SELECT sum(n) FROM tb) = 184 AS match
UNION ALL SELECT 'W2 tracebacks (file,pid,ts groups)', '8', (SELECT count(*) FROM tb)::VARCHAR, (SELECT count(*) FROM tb) = 8
UNION ALL SELECT 'W2 lines per traceback min..max', '23..23',
       (SELECT min(n) || '..' || max(n) FROM tb), (SELECT min(n) = 23 AND max(n) = 23 FROM tb)
UNION ALL SELECT 'W2 exact Traceback lines (all loggers)', '8',
       (SELECT count(*) FROM read_parquet('/data/loghub/openstack.parquet') WHERE message = 'Traceback (most recent call last):')::VARCHAR,
       (SELECT count(*) FROM read_parquet('/data/loghub/openstack.parquet') WHERE message = 'Traceback (most recent call last):') = 8
UNION ALL SELECT 'W2 tracebacks with 1 Traceback line', '8', (SELECT count(*) FROM tb WHERE n_tb = 1)::VARCHAR,
       (SELECT count(*) FROM tb WHERE n_tb = 1) = 8
UNION ALL SELECT 'W2 tracebacks with exact header line', '8', (SELECT count(*) FROM tb WHERE n_hdr = 1)::VARCHAR,
       (SELECT count(*) FROM tb WHERE n_hdr = 1) = 8
UNION ALL SELECT 'W2 tracebacks with ^InvalidDiskInfo: line', '8', (SELECT count(*) FROM tb WHERE n_exc = 1)::VARCHAR,
       (SELECT count(*) FROM tb WHERE n_exc = 1) = 8
UNION ALL SELECT 'W2 min gap between tracebacks (s)', '>= 300', (SELECT round(min(gap_s), 3) FROM g)::VARCHAR,
       (SELECT min(gap_s) >= 300 FROM g);

-- W2 second source: os_ev, and the header is the first line of each group by id (file order)
WITH tb AS (SELECT source_file, pid, ts, count(*) AS n, min(id) AS first_id, max(id) - min(id) + 1 AS id_span,
                   min(id) FILTER (WHERE content = 'Error during ComputeManager._run_image_cache_manager_pass') AS hdr_id
            FROM os_ev WHERE level = 'ERROR' AND logger = 'oslo_service.periodic_task'
            GROUP BY source_file, pid, ts)
SELECT 'W2 os_ev: groups / lines / header first / contiguous ids' AS claim, '8 / 184 / 8 / 8' AS stated,
       count(*) || ' / ' || sum(n) || ' / ' || count(*) FILTER (WHERE hdr_id = first_id) || ' / '
                || count(*) FILTER (WHERE id_span = n) AS independent,
       count(*) = 8 AND sum(n) = 184 AND count(*) FILTER (WHERE hdr_id = first_id) = 8
                AND count(*) FILTER (WHERE id_span = n) = 8 AS match
FROM tb;

-- ---------------------------------------------------------------------------------------------
-- W3. keystonemiddleware.auth_token: 6 lines = 2 CRITICAL + 2 ERROR + 2 WARNING, 2 requests x 3
--   lines (2017-05-16 06:25:02.867-.869, 2017-05-17 06:25:03.044-.046); the 2 CRITICAL lines are the
--   only CRITICAL lines. Also: ERROR + CRITICAL in the corpus = 188 = 184 (8 tracebacks) + 4 auth lines.
-- ---------------------------------------------------------------------------------------------
WITH a AS (SELECT level, request_id, "timestamp"::timestamp AS t
           FROM read_parquet('/data/loghub/openstack.parquet') WHERE logger = 'keystonemiddleware.auth_token'),
r AS (SELECT request_id, count(*) AS n, min(t) AS t0, max(t) AS t1 FROM a GROUP BY request_id)
SELECT 'W3 auth_token lines' AS claim, '6' AS stated, (SELECT count(*) FROM a)::VARCHAR AS independent,
       (SELECT count(*) FROM a) = 6 AS match
UNION ALL SELECT 'W3 auth_token CRITICAL/ERROR/WARNING', '2/2/2',
       (SELECT count(*) FILTER (WHERE level = 'CRITICAL') || '/' || count(*) FILTER (WHERE level = 'ERROR') || '/'
               || count(*) FILTER (WHERE level = 'WARNING') FROM a),
       (SELECT count(*) FILTER (WHERE level = 'CRITICAL') = 2 AND count(*) FILTER (WHERE level = 'ERROR') = 2
               AND count(*) FILTER (WHERE level = 'WARNING') = 2 FROM a)
UNION ALL SELECT 'W3 auth_token requests x lines', '2 x 3',
       (SELECT count(*) || ' x ' || min(n) || '..' || max(n) FROM r), (SELECT count(*) = 2 AND min(n) = 3 AND max(n) = 3 FROM r)
UNION ALL SELECT 'W3 request ' || (row_number() OVER (ORDER BY t0))::VARCHAR || ' span',
       CASE WHEN t0 < TIMESTAMP '2017-05-17' THEN '2017-05-16 ~06:25:02' ELSE '2017-05-17 ~06:25:03' END,
       t0::VARCHAR || ' .. ' || t1::VARCHAR,
       date_trunc('second', t0) IN (TIMESTAMP '2017-05-16 06:25:02', TIMESTAMP '2017-05-17 06:25:03')
FROM r
UNION ALL SELECT 'W3 CRITICAL lines, all loggers / non-auth', '2 / 0',
       (SELECT count(*) || ' / ' || count(*) FILTER (WHERE logger <> 'keystonemiddleware.auth_token')
        FROM read_parquet('/data/loghub/openstack.parquet') WHERE level = 'CRITICAL'),
       (SELECT count(*) = 2 AND count(*) FILTER (WHERE logger <> 'keystonemiddleware.auth_token') = 0
        FROM read_parquet('/data/loghub/openstack.parquet') WHERE level = 'CRITICAL')
UNION ALL SELECT 'W3 wording: ERROR+CRITICAL lines = periodic_task + auth_token', '188 = 184 + 4',
       (SELECT count(*) || ' = ' || count(*) FILTER (WHERE logger = 'oslo_service.periodic_task') || ' + '
               || count(*) FILTER (WHERE logger = 'keystonemiddleware.auth_token')
        FROM read_parquet('/data/loghub/openstack.parquet') WHERE level IN ('ERROR', 'CRITICAL')),
       (SELECT count(*) = 188 AND count(*) FILTER (WHERE logger = 'oslo_service.periodic_task') = 184
               AND count(*) FILTER (WHERE logger = 'keystonemiddleware.auth_token') = 4
        FROM read_parquet('/data/loghub/openstack.parquet') WHERE level IN ('ERROR', 'CRITICAL'));

-- ---------------------------------------------------------------------------------------------
-- W4. nova.virt.libvirt.imagecache WARNING 'Unknown base file: ...' = 3059 lines; new incident when
--   the gap to the previous such line is > 300 s -> 3 incidents.
--   expected splitting gaps 93869.761 s (26h04m29.761s) and 31870.635 s (8h51m10.635s); largest
--   in-incident gap 74.187 s, so any gap threshold in [75 s, 31870 s] gives 3. The splits coincide
--   with the three file boundaries (abnormal 05-14, normal1 05-16 00:00-06:25, normal2 from 15:15).
-- ---------------------------------------------------------------------------------------------
WITH w AS (SELECT origin_file, "timestamp"::timestamp AS t FROM read_parquet('/data/loghub/openstack.parquet')
           WHERE logger = 'nova.virt.libvirt.imagecache' AND level = 'WARNING'
             AND regexp_matches(message, '^Unknown base file: ')),
g AS (SELECT origin_file, t, extract(epoch FROM t) - extract(epoch FROM lag(t) OVER (ORDER BY t)) AS gap_s FROM w),
k AS (SELECT origin_file, t, gap_s,
             sum(CASE WHEN gap_s IS NULL OR gap_s > 300 THEN 1 ELSE 0 END) OVER (ORDER BY t ROWS UNBOUNDED PRECEDING) AS inc
      FROM g)
SELECT 'W4 Unknown base file WARNING lines' AS claim, '3059' AS stated, (SELECT count(*) FROM w)::VARCHAR AS independent,
       (SELECT count(*) FROM w) = 3059 AS match
UNION ALL SELECT 'W4 imagecache WARNING lines (any message)', '3059',
       (SELECT count(*) FROM read_parquet('/data/loghub/openstack.parquet')
        WHERE logger = 'nova.virt.libvirt.imagecache' AND level = 'WARNING')::VARCHAR,
       (SELECT count(*) FROM read_parquet('/data/loghub/openstack.parquet')
        WHERE logger = 'nova.virt.libvirt.imagecache' AND level = 'WARNING') = 3059
UNION ALL SELECT 'W4 incidents, gap > 5 min', '3', (SELECT max(inc) FROM k)::VARCHAR, (SELECT max(inc) = 3 FROM k)
UNION ALL SELECT 'W4 incident ' || inc::VARCHAR || ': lines, span, gap before (s), file', '-',
       count(*) || ' lines, ' || min(t) || ' .. ' || max(t) || ', gap '
                || coalesce(round(max(gap_s) FILTER (WHERE gap_s > 300), 3)::VARCHAR, 'first') || ', ' || min(origin_file),
       count(DISTINCT origin_file) = 1
FROM k GROUP BY inc
UNION ALL SELECT 'W4 largest gap inside an incident (s)', '<= 300',
       (SELECT round(max(gap_s) FILTER (WHERE gap_s <= 300), 3) FROM g)::VARCHAR, (SELECT max(gap_s) FILTER (WHERE gap_s <= 300) <= 300 FROM g)
ORDER BY 1;

-- ---------------------------------------------------------------------------------------------
-- W5. Instance lifecycle per instance_id (raw Parquet, exact message equality with the instance prefix).
--   spawn_s = N in '... Took N seconds to spawn the instance on the hypervisor.'
--   image   = 'Creating image' -> 'VM Started (Lifecycle Event)'; boot = 'VM Started' -> 'Instance spawned successfully.'
--   Every instance has at most one line of each kind. 2066 instances have spawn_s; image is defined for
--   2065 (b9000564-... has no 'Creating image': normal1 starts mid-lifecycle); boot for 2066.
--   expected by spawn: 1 a445709b 50.72 · 2 544fd51c 41.81 · 3 1643649d 31.27 · 4 ae651dff 29.46 · 5 d7d68893 26.69
--   expected by image: same four 1-4 (44.454, 34.647, 25.217, 22.444), 5 = d7d68893 19.808
--   medians (quantile_cont = linear interpolation): spawn 19.74, image 13.08, boot 6.648
--   labelled boot phases 6.047 .. 7.164
-- ---------------------------------------------------------------------------------------------
WITH r AS (SELECT instance_id AS iid, "timestamp"::timestamp AS t, message AS m
           FROM read_parquet('/data/loghub/openstack.parquet') WHERE instance_id IS NOT NULL AND instance_id <> ''),
p AS (SELECT iid,
             max(CAST(nullif(regexp_extract(m, 'Took ([0-9.]+) seconds to spawn the instance on the hypervisor\.$', 1), '') AS DOUBLE)) AS spawn_s,
             min(t) FILTER (WHERE m = '[instance: ' || iid || '] Creating image') AS t_ci,
             min(t) FILTER (WHERE m = '[instance: ' || iid || '] VM Started (Lifecycle Event)') AS t_vs,
             min(t) FILTER (WHERE m = '[instance: ' || iid || '] Instance spawned successfully.') AS t_ss
      FROM r GROUP BY iid),
d AS (SELECT iid, spawn_s,
             extract(epoch FROM t_vs) - extract(epoch FROM t_ci) AS image_s,
             extract(epoch FROM t_ss) - extract(epoch FROM t_vs) AS boot_s,
             iid IN ('544fd51c-4edc-4780-baae-ba1d80a0acfc', 'ae651dff-c7ad-43d6-ac96-bbcd820ccca8',
                     'a445709b-6ad0-40ec-8860-bec60b6ca0c2', '1643649d-2f42-4303-bfcd-7798baec19f9') AS labelled
      FROM p WHERE spawn_s IS NOT NULL),
k AS (SELECT *, rank() OVER (ORDER BY spawn_s DESC) AS rk_spawn,
                rank() OVER (ORDER BY image_s DESC NULLS LAST) AS rk_image FROM d)
SELECT 'W5 spawn rank ' || rk_spawn::VARCHAR || ' (' || CASE WHEN labelled THEN 'labelled' ELSE 'unlabelled' END || ')' AS claim,
       CASE rk_spawn WHEN 1 THEN '50.72' WHEN 2 THEN '41.81' WHEN 3 THEN '31.27' WHEN 4 THEN '29.46' ELSE '26.69 d7d68893' END AS stated,
       left(iid, 8) || ' spawn ' || spawn_s || ' image ' || round(image_s, 3) || ' boot ' || round(boot_s, 3) AS independent,
       CASE rk_spawn WHEN 1 THEN spawn_s = 50.72 WHEN 2 THEN spawn_s = 41.81 WHEN 3 THEN spawn_s = 31.27
                     WHEN 4 THEN spawn_s = 29.46 ELSE spawn_s = 26.69 AND left(iid, 8) = 'd7d68893' END
         AND (labelled = (rk_spawn <= 4)) AS match
FROM k WHERE rk_spawn <= 5
UNION ALL
SELECT 'W5 image rank ' || rk_image::VARCHAR, CASE rk_image WHEN 1 THEN '44.454' WHEN 2 THEN '34.647' WHEN 3 THEN '25.217'
                                               WHEN 4 THEN '22.444' ELSE '19.808' END,
       left(iid, 8) || ' image ' || round(image_s, 3),
       round(image_s, 3) = CASE rk_image WHEN 1 THEN 44.454 WHEN 2 THEN 34.647 WHEN 3 THEN 25.217 WHEN 4 THEN 22.444 ELSE 19.808 END
         AND (labelled = (rk_image <= 4))
FROM k WHERE rk_image <= 5
UNION ALL
SELECT 'W5 instances with spawn / image / boot', '-', count(*) || ' / ' || count(image_s) || ' / ' || count(boot_s), true FROM d
UNION ALL
SELECT 'W5 median spawn_s (quantile_cont | percentile_cont)', '19.74',
       quantile_cont(spawn_s, 0.5) || ' | ' || percentile_cont(0.5) WITHIN GROUP (ORDER BY spawn_s),
       abs(quantile_cont(spawn_s, 0.5) - 19.74) < 0.005 FROM d
UNION ALL
SELECT 'W5 median image_s (quantile_cont | percentile_cont)', '13.08',
       round(quantile_cont(image_s, 0.5), 6) || ' | ' || round(percentile_cont(0.5) WITHIN GROUP (ORDER BY image_s), 6),
       abs(quantile_cont(image_s, 0.5) - 13.08) < 0.005 FROM d
UNION ALL
SELECT 'W5 median boot_s (quantile_cont | percentile_cont)', '6.65',
       round(quantile_cont(boot_s, 0.5), 6) || ' | ' || round(percentile_cont(0.5) WITHIN GROUP (ORDER BY boot_s), 6),
       abs(quantile_cont(boot_s, 0.5) - 6.65) < 0.005 FROM d
UNION ALL
SELECT 'W5 labelled boot phase min..max', '6.0..7.2', round(min(boot_s), 3) || '..' || round(max(boot_s), 3),
       round(min(boot_s), 1) = 6.0 AND round(max(boot_s), 1) = 7.2 FROM d WHERE labelled
ORDER BY 1;

-- W5 second source: os_ev.spawn_s (the derive step's extraction)
SELECT 'W5 os_ev spawn_s rows / instances / median / top5' AS claim, '2066 / 2066 / 19.74 / ...' AS stated,
       count(*) || ' / ' || count(DISTINCT instance_id) || ' / ' || quantile_cont(spawn_s, 0.5) AS independent,
       count(*) = 2066 AND count(DISTINCT instance_id) = 2066 AND quantile_cont(spawn_s, 0.5) = 19.74 AS match
FROM os_ev WHERE spawn_s IS NOT NULL;
SELECT row_number() OVER (ORDER BY spawn_s DESC) AS pos, instance_id, spawn_s
FROM os_ev WHERE spawn_s IS NOT NULL ORDER BY spawn_s DESC LIMIT 5;

-- ---------------------------------------------------------------------------------------------
-- W6. API latency, rows with a parsed latency_s (98733 rows; every one also has a status_code).
--   expected abnormal 9416 calls, mean 0.2340, p95 0.3771; normal1+normal2 89317, mean 0.2341, p95 0.3826
--   p95 = quantile_cont (linear interpolation); percentile_cont gives the same value; quantile_disc shown.
-- ---------------------------------------------------------------------------------------------
WITH l AS (SELECT CASE WHEN origin_file = 'openstack_abnormal.log' THEN 'abnormal' ELSE 'normal1+normal2' END AS grp, latency_s
           FROM read_parquet('/data/loghub/openstack.parquet') WHERE latency_s IS NOT NULL),
a AS (SELECT grp, count(*) AS calls, avg(latency_s) AS mean_s, quantile_cont(latency_s, 0.95) AS p95_cont,
             percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_s) AS p95_pct, quantile_disc(latency_s, 0.95) AS p95_disc
      FROM l GROUP BY grp),
s(grp, calls, mean_s, p95) AS (VALUES ('abnormal', 9416, 0.2340, 0.3771), ('normal1+normal2', 89317, 0.2341, 0.3826))
SELECT 'W6 ' || a.grp || ' calls / mean / p95' AS claim,
       s.calls || ' / ' || s.mean_s || ' / ' || s.p95 AS stated,
       a.calls || ' / ' || round(a.mean_s, 6) || ' / ' || round(a.p95_cont, 6) || ' (pct_cont ' || round(a.p95_pct, 6)
               || ', disc ' || a.p95_disc || ')' AS independent,
       a.calls = s.calls AND round(a.mean_s, 4) = s.mean_s AND round(a.p95_cont, 4) = s.p95 AS match
FROM a JOIN s USING (grp) ORDER BY 1;

-- W6 second source: os_ev
SELECT 'W6 os_ev ' || CASE WHEN source_file = 'openstack_abnormal.log' THEN 'abnormal' ELSE 'normal1+normal2' END AS claim,
       count(latency_s) AS calls, round(avg(latency_s), 6) AS mean_s, round(quantile_cont(latency_s, 0.95), 6) AS p95_cont
FROM os_ev WHERE latency_s IS NOT NULL GROUP BY 1 ORDER BY 1;
