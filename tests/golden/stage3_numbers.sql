-- tests/golden/stage3_numbers.sql
-- Independent recomputation of the numbers `make demo` prints (sql/90_queries.sql, W1 BGL and W2
-- OpenStack) that tests/golden/w2_numbers.sql and headline_numbers.sql do not already cover
-- (sql-verifier, 17 Oct 2026).
-- Written fresh: it does not use sql/30_views.sql, sql/50_roles.sql, sql/90_queries.sql,
-- sql/99_smoke.sql, logs/demo-*.log, or any view (bgl_sig, bgl_episode, bgl_incident,
-- bgl_signature_incidents, bgl_signature_stats, bgl_episode_sensitivity, ownership_coverage, os_sig,
-- os_episode, os_incident, os_problem_incidents, os_instance_durations, os_latency_by_file, lead_*,
-- mgr_*). Read-only: SELECTs only, no DDL, no writes.
-- Primary source is the raw Parquet plus data/ownership.csv (read with read_csv); bgl_ev, os_ev and
-- owner_map are a second source where useful, with a differently written formulation.
--
-- Run (Windows host, no host psql):
--   export MSYS_NO_PATHCONV=1
--   docker exec -i serenedb psql -h 127.0.0.1 -p 7890 -U postgres -P pager=off -f - < tests/golden/stage3_numbers.sql
--
-- Operators:
--   * full text: exactly one claim (S3) uses `content @@ ts_phrase('data TLB error interrupt')`, run
--     against the index relation bgl_idx (never bgl_ev, where @@ fails). Exact equality on the raw
--     content is shown beside it as a NOTE only, never as support.
--   * everything else: equality / inequality on label, level, logger, component, file; regexp_replace
--     masking (UUID 8-4-4-4-12 hex -> '{uuid}' first, then [0-9]+ -> '{n}'); regexp_extract (wrapped
--     in nullif(x, '') because it returns '' on no match) and regexp_matches / ~ to recognise fixed
--     shapes; LAG and ROWS-frame windows for episodes; dense_rank / rank / row_number; regr_slope;
--     quantile_cont and percentile_cont (both LINEAR interpolation; quantile_disc shown as a note).
--   * no LIKE / ILIKE anywhere.
-- Definitions used (from the task statement, not from the views):
--   alert line   raw label <> '-'
--   signature    content, UUIDs -> '{uuid}', then digit runs -> '{n}'; signature_id = left(md5(sig), 12)
--   midplane     split_part(node,'-',1) || '-' || split_part(node,'-',2) when node has >= 2 '-', else 'UNKNOWN'
--   team (BGL)   data/ownership.csv row (BGL, component, <component>), else 'UNOWNED'
--   episode      over the alert lines of one signature in ts order, new at the first line or when the
--                gap to the previous line is strictly greater than the threshold; scope "domain"
--                partitions by (signature, midplane), "global" by signature only
-- Timestamps: the Parquet "timestamp" is VARCHAR and is cast with ::timestamp. BGL ts is US Pacific
-- wall clock (docs/data-notes.md); calendar days and weeks below are on that wall clock, as stated.
-- Floats: counts compare exactly; rounded stated values compare as abs(round(x, k) - stated) < 1e-9.

\set ON_ERROR_STOP on
SET statement_timeout = '120s';  -- accepted but NOT enforced by serened 26.09.1.3 (it warns)

-- =============================================================================================
-- S1 (claim 1). BGL lines, alert lines, first and last ts.
--   expected 4747963 lines, 348460 alert lines, 2005-06-03 15:42:50.363779 .. 2006-01-04 08:00:05.233639
-- =============================================================================================
WITH r AS (SELECT count(*) AS n, count(*) FILTER (WHERE label <> '-') AS al,
                  min("timestamp"::timestamp) AS t0, max("timestamp"::timestamp) AS t1
           FROM read_parquet('/data/loghub/bgl.parquet')),
e AS (SELECT count(*) AS n, count(*) FILTER (WHERE alert_category <> '-') AS al, min(ts) AS t0, max(ts) AS t1 FROM bgl_ev)
SELECT 'S1 BGL lines (parquet | bgl_ev)' AS claim, '4747963' AS stated, r.n || ' | ' || e.n AS independent,
       r.n = 4747963 AND e.n = 4747963 AS match FROM r, e
UNION ALL SELECT 'S1 BGL alert lines (parquet | bgl_ev)', '348460', r.al || ' | ' || e.al, r.al = 348460 AND e.al = 348460 FROM r, e
UNION ALL SELECT 'S1 BGL first ts (parquet | bgl_ev)', '2005-06-03 15:42:50.363779', r.t0 || ' | ' || e.t0,
       r.t0 = TIMESTAMP '2005-06-03 15:42:50.363779' AND e.t0 = r.t0 FROM r, e
UNION ALL SELECT 'S1 BGL last ts (parquet | bgl_ev)', '2006-01-04 08:00:05.233639', r.t1 || ' | ' || e.t1,
       r.t1 = TIMESTAMP '2006-01-04 08:00:05.233639' AND e.t1 = r.t1 FROM r, e;

-- =============================================================================================
-- S2 (claim 2). Top 5 alert signatures by alert lines: lines / 5-min domain episodes / nodes_affected /
--   top-node share (%, 2 dp). Exactly 100 alert signatures.
--   No tie at the cut: #5 has 18587 lines, #6 15273.
-- =============================================================================================
WITH a AS (
  SELECT "timestamp"::timestamp AS t, node,
         regexp_replace(regexp_replace(content,
           '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig,
         CASE WHEN length(node) - length(replace(node, '-', '')) >= 2
              THEN split_part(node, '-', 1) || '-' || split_part(node, '-', 2) ELSE 'UNKNOWN' END AS mp
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'),
st AS (SELECT sig, t, lag(t) OVER (PARTITION BY sig, mp ORDER BY t) AS prev FROM a),
ep AS (SELECT sig, count(*) FILTER (WHERE prev IS NULL OR t - prev > INTERVAL '5 minutes') AS eps FROM st GROUP BY sig),
pn AS (SELECT sig, node, count(*) AS n FROM a GROUP BY sig, node),
sg AS (SELECT sig, sum(n) AS lines, count(*) AS nodes, max(n) AS top_n FROM pn GROUP BY sig),
k AS (SELECT row_number() OVER (ORDER BY lines DESC) AS pos, sig, lines, eps, nodes,
             round(CAST(top_n AS DOUBLE) * 100 / lines, 2) AS top_pct FROM sg JOIN ep USING (sig)),
s(pos, sig, lines, eps, nodes, top_pct) AS (VALUES
  (1, 'data TLB error interrupt', 152734, 117, 541, 99.64),
  (2, 'data storage interrupt', 63491, 133, 22529, 0.01),
  (3, 'ciod: Error reading message prefix on CioStream socket to {n}.{n}.{n}.{n}:{n}, Link has been severed', 26546, 3638, 1024, 0.13),
  (4, 'Lustre mount FAILED : bglio{n} : point /p/gb{n}', 26426, 3667, 1024, 0.16),
  (5, 'rts: kernel terminated for reason {n}', 18587, 2641, 7650, 0.12))
SELECT 'S2 by lines #' || s.pos || ' ' || left(s.sig, 48) AS claim,
       s.lines || ' / ' || s.eps || ' / ' || s.nodes || ' / ' || s.top_pct AS stated,
       k.lines || ' / ' || k.eps || ' / ' || k.nodes || ' / ' || k.top_pct || ' [' || left(md5(k.sig), 12) || ']' AS independent,
       k.sig = s.sig AND k.lines = s.lines AND k.eps = s.eps AND k.nodes = s.nodes
         AND abs(k.top_pct - s.top_pct) < 1e-9 AS match
FROM s LEFT JOIN k USING (pos)
UNION ALL
SELECT 'S2 alert signatures (distinct)', '100', count(*)::VARCHAR, count(*) = 100 FROM sg
ORDER BY 1;

-- S2 second source: bgl_ev, masking written differently ((?i) hex class, \d+), lines and nodes only
WITH a AS (SELECT node, regexp_replace(regexp_replace(content, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
                                       '{uuid}', 'g'), '\d+', '{n}', 'g') AS sig
           FROM bgl_ev WHERE is_alert),
g AS (SELECT sig, count(*) AS lines, count(DISTINCT node) AS nodes FROM a GROUP BY sig)
SELECT 'S2 bgl_ev: signatures / top-5 lines / top-5 nodes' AS claim,
       '100 / 152734,63491,26546,26426,18587 / 541,22529,1024,1024,7650' AS stated,
       (SELECT count(*) FROM g) || ' / ' || (SELECT string_agg(lines::VARCHAR, ',' ORDER BY lines DESC) FROM (SELECT lines FROM g ORDER BY lines DESC LIMIT 5) x)
         || ' / ' || (SELECT string_agg(nodes::VARCHAR, ',' ORDER BY lines DESC) FROM (SELECT lines, nodes FROM g ORDER BY lines DESC LIMIT 5) y) AS independent,
       (SELECT count(*) FROM g) = 100
         AND (SELECT string_agg(lines::VARCHAR, ',' ORDER BY lines DESC) FROM (SELECT lines FROM g ORDER BY lines DESC LIMIT 5) x) = '152734,63491,26546,26426,18587'
         AND (SELECT string_agg(nodes::VARCHAR, ',' ORDER BY lines DESC) FROM (SELECT lines, nodes FROM g ORDER BY lines DESC LIMIT 5) y) = '541,22529,1024,1024,7650' AS match;

-- =============================================================================================
-- S3 (claim 3). Full text, operator `@@ ts_phrase(...)` against the index relation bgl_idx.
--   expected 152734 matches; top node R30-M0-N9-C:J16-U01 152182 lines, 2005-06-11 17:17:44.898186
--   .. 23:39:32.87774 (span 06:21:47.979554); next two nodes 3 lines each.
--   TIE: three nodes have exactly 3 lines, so "the next two" is an arbitrary pick of two of three.
-- =============================================================================================
WITH p AS (SELECT node, ts, alert_category FROM bgl_idx WHERE content @@ ts_phrase('data TLB error interrupt')),
pn AS (SELECT node, count(*) AS n, min(ts) AS t0, max(ts) AS t1 FROM p GROUP BY node),
rk AS (SELECT *, row_number() OVER (ORDER BY n DESC, node) AS rn FROM pn)
SELECT 'S3 @@ ts_phrase matches (bgl_idx)' AS claim, '152734' AS stated, (SELECT count(*) FROM p)::VARCHAR AS independent,
       (SELECT count(*) FROM p) = 152734 AS match
UNION ALL SELECT 'S3 top node / lines', 'R30-M0-N9-C:J16-U01 / 152182', node || ' / ' || n,
       node = 'R30-M0-N9-C:J16-U01' AND n = 152182 FROM rk WHERE rn = 1
UNION ALL SELECT 'S3 top node first .. last', '2005-06-11 17:17:44.898186 .. 23:39:32.87774', t0 || ' .. ' || t1,
       t0 = TIMESTAMP '2005-06-11 17:17:44.898186' AND t1 = TIMESTAMP '2005-06-11 23:39:32.87774' FROM rk WHERE rn = 1
UNION ALL SELECT 'S3 top node span', '06:21:47.979554', (t1 - t0)::VARCHAR,
       abs(extract(epoch FROM t1) - extract(epoch FROM t0) - (6 * 3600 + 21 * 60 + 47.979554)) < 1e-6 FROM rk WHERE rn = 1
UNION ALL SELECT 'S3 lines on nodes ranked 2 and 3', '3, 3', string_agg(n::VARCHAR, ', ' ORDER BY rn),
       min(n) = 3 AND max(n) = 3 FROM rk WHERE rn IN (2, 3)
UNION ALL SELECT 'S3 NOTE tie: nodes with exactly 3 lines', '(2 shown)', count(*)::VARCHAR, NULL FROM pn WHERE n = 3
UNION ALL SELECT 'S3 NOTE matches that are alert lines', '-', count(*) FILTER (WHERE alert_category <> '-')::VARCHAR, NULL FROM p
UNION ALL SELECT 'S3 NOTE raw content = phrase (equality, not support)', '-',
       (SELECT count(*) FROM read_parquet('/data/loghub/bgl.parquet') WHERE content = 'data TLB error interrupt')::VARCHAR, NULL
ORDER BY 1;

-- =============================================================================================
-- S4 (claim 4). Alert lines per ts calendar day.   expected 2005-06-11 152183 lines / 1 node;
--   2005-06-14 49154 lines / 22529 nodes. (Parquet: cast to DATE; bgl_ev: half-open ts range.)
-- =============================================================================================
WITH s(d, lines, nodes) AS (VALUES (DATE '2005-06-11', 152183, 1), (DATE '2005-06-14', 49154, 22529)),
r AS (SELECT CAST("timestamp"::timestamp AS DATE) AS d, count(*) AS lines, count(DISTINCT node) AS nodes
      FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-' GROUP BY 1),
e AS (SELECT s.d, count(*) AS lines, count(DISTINCT b.node) AS nodes FROM s JOIN bgl_ev b
        ON b.ts >= CAST(s.d AS TIMESTAMP) AND b.ts < CAST(s.d AS TIMESTAMP) + INTERVAL '1 day' AND b.alert_category <> '-'
      GROUP BY s.d)
SELECT 'S4 alert lines / nodes on ' || s.d AS claim, s.lines || ' / ' || s.nodes AS stated,
       r.lines || ' / ' || r.nodes || ' (bgl_ev ' || e.lines || ' / ' || e.nodes || ')' AS independent,
       r.lines = s.lines AND r.nodes = s.nodes AND e.lines = s.lines AND e.nodes = s.nodes AS match
FROM s LEFT JOIN r USING (d) LEFT JOIN e USING (d) ORDER BY s.d;

-- =============================================================================================
-- S5 (claim 5). 'data TLB error interrupt' episodes at 1 / 5 / 60 min, domain and global; totals over
--   all alert signatures at 5 min.  expected domain 132/117/57, global 37/37/16; totals 19250 / 1377.
--   Gaps on extract(epoch) as DOUBLE seconds. Boundary: no gap lies within 1 ms of 60, 300 or 3600 s
--   (NOTE row), so '>' and '>=' agree at all three thresholds.
-- =============================================================================================
WITH a AS (
  SELECT extract(epoch FROM "timestamp"::timestamp) AS e,
         regexp_replace(regexp_replace(content,
           '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig,
         CASE WHEN length(node) - length(replace(node, '-', '')) >= 2
              THEN split_part(node, '-', 1) || '-' || split_part(node, '-', 2) ELSE 'UNKNOWN' END AS mp
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'),
g AS (SELECT sig, e - lag(e) OVER (PARTITION BY sig, mp ORDER BY e) AS gd,
                  e - lag(e) OVER (PARTITION BY sig ORDER BY e) AS gg FROM a),
c AS (SELECT sig = 'data TLB error interrupt' AS tlb,
             count(*) FILTER (WHERE gd IS NULL OR gd > 60) AS d1, count(*) FILTER (WHERE gd IS NULL OR gd > 300) AS d5,
             count(*) FILTER (WHERE gd IS NULL OR gd > 3600) AS d60,
             count(*) FILTER (WHERE gg IS NULL OR gg > 60) AS g1, count(*) FILTER (WHERE gg IS NULL OR gg > 300) AS g5,
             count(*) FILTER (WHERE gg IS NULL OR gg > 3600) AS g60,
             count(*) FILTER (WHERE abs(gd - 60) < 0.001 OR abs(gd - 300) < 0.001 OR abs(gd - 3600) < 0.001
                                 OR abs(gg - 60) < 0.001 OR abs(gg - 300) < 0.001 OR abs(gg - 3600) < 0.001) AS near
      FROM g GROUP BY 1)
SELECT 'S5 TLB domain episodes 1/5/60 min' AS claim, '132 / 117 / 57' AS stated, d1 || ' / ' || d5 || ' / ' || d60 AS independent,
       d1 = 132 AND d5 = 117 AND d60 = 57 AS match FROM c WHERE tlb
UNION ALL SELECT 'S5 TLB global episodes 1/5/60 min', '37 / 37 / 16', g1 || ' / ' || g5 || ' / ' || g60,
       g1 = 37 AND g5 = 37 AND g60 = 16 FROM c WHERE tlb
UNION ALL SELECT 'S5 all alert signatures, 5 min, domain / global', '19250 / 1377', sum(d5) || ' / ' || sum(g5),
       sum(d5) = 19250 AND sum(g5) = 1377 FROM c
UNION ALL SELECT 'S5 NOTE gaps within 1 ms of 60/300/3600 s', '0', sum(near)::VARCHAR, sum(near) = 0 FROM c
ORDER BY 1;

-- S5 second source: bgl_ev, ROWS-frame previous ts, INTERVAL comparison, TLB only
WITH a AS (SELECT ts, midplane AS mp FROM bgl_ev WHERE is_alert AND content = 'data TLB error interrupt'),
p AS (SELECT ts, max(ts) OVER (PARTITION BY mp ORDER BY ts ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING) AS pd,
             max(ts) OVER (ORDER BY ts ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING) AS pg FROM a)
SELECT 'S5 bgl_ev TLB domain 1/5/60 | global 1/5/60' AS claim, '132/117/57 | 37/37/16' AS stated,
       count(*) FILTER (WHERE pd IS NULL OR ts - pd > INTERVAL '1 minute') || '/' || count(*) FILTER (WHERE pd IS NULL OR ts - pd > INTERVAL '5 minutes')
         || '/' || count(*) FILTER (WHERE pd IS NULL OR ts - pd > INTERVAL '60 minutes') || ' | '
         || count(*) FILTER (WHERE pg IS NULL OR ts - pg > INTERVAL '1 minute') || '/' || count(*) FILTER (WHERE pg IS NULL OR ts - pg > INTERVAL '5 minutes')
         || '/' || count(*) FILTER (WHERE pg IS NULL OR ts - pg > INTERVAL '60 minutes') AS independent,
       count(*) FILTER (WHERE pd IS NULL OR ts - pd > INTERVAL '1 minute') = 132
         AND count(*) FILTER (WHERE pd IS NULL OR ts - pd > INTERVAL '5 minutes') = 117
         AND count(*) FILTER (WHERE pd IS NULL OR ts - pd > INTERVAL '60 minutes') = 57
         AND count(*) FILTER (WHERE pg IS NULL OR ts - pg > INTERVAL '1 minute') = 37
         AND count(*) FILTER (WHERE pg IS NULL OR ts - pg > INTERVAL '5 minutes') = 37
         AND count(*) FILTER (WHERE pg IS NULL OR ts - pg > INTERVAL '60 minutes') = 16 AS match
FROM p;

-- =============================================================================================
-- S6 (claim 6). BGL lines and alert lines per team (data/ownership.csv by component).
--   Shares: lines / 4747963 and alert lines / 348460, DOUBLE, 2 dp. No UNOWNED lines.
-- =============================================================================================
WITH om AS (SELECT key_value, team FROM read_csv('/data/ownership.csv') WHERE dataset = 'BGL' AND key_type = 'component'),
r AS (SELECT coalesce(om.team, 'UNOWNED') AS team, count(*) AS lines, count(*) FILTER (WHERE b.label <> '-') AS alert
      FROM read_parquet('/data/loghub/bgl.parquet') b LEFT JOIN om ON om.key_value = b.component GROUP BY 1),
t AS (SELECT sum(lines) AS tl, sum(alert) AS ta FROM r),
s(team, lines, pct, alert, apct) AS (VALUES
  ('compute-platform', 4325112, CAST(91.09 AS DOUBLE), 284391, CAST(81.61 AS DOUBLE)),
  ('workload-runtime', 228536, 4.81, 63845, 18.32),
  ('observability', 99064, 2.09, 15, NULL),
  ('storage-platform', 88930, 1.87, 3, NULL),
  ('site-infrastructure', 5148, 0.11, 0, NULL),
  ('network-fabric', 1173, 0.02, 206, 0.06))
SELECT 'S6 team ' || s.team || ' lines (%) / alert lines (%)' AS claim,
       s.lines || ' (' || s.pct || ') / ' || s.alert || coalesce(' (' || s.apct || ')', '') AS stated,
       r.lines || ' (' || round(CAST(r.lines AS DOUBLE) * 100 / t.tl, 2) || ') / ' || r.alert
         || ' (' || round(CAST(r.alert AS DOUBLE) * 100 / t.ta, 2) || ')' AS independent,
       r.lines = s.lines AND r.alert = s.alert AND abs(round(CAST(r.lines AS DOUBLE) * 100 / t.tl, 2) - s.pct) < 1e-9
         AND (s.apct IS NULL OR abs(round(CAST(r.alert AS DOUBLE) * 100 / t.ta, 2) - s.apct) < 1e-9) AS match
FROM s LEFT JOIN r USING (team) CROSS JOIN t
UNION ALL
SELECT 'S6 UNOWNED lines / total lines / total alert lines', '0 / 4747963 / 348460',
       coalesce((SELECT lines FROM r WHERE team = 'UNOWNED'), 0) || ' / ' || t.tl || ' / ' || t.ta,
       coalesce((SELECT lines FROM r WHERE team = 'UNOWNED'), 0) = 0 AND t.tl = 4747963 AND t.ta = 348460 FROM t
ORDER BY 1;

-- S6 second source: bgl_ev.component joined to owner_map (not bgl_ev.team), and bgl_ev.team as stored
WITH j AS (SELECT coalesce(o.team, 'UNOWNED') AS team, b.team AS stored, b.is_alert
           FROM bgl_ev b LEFT JOIN owner_map o ON o.dataset = 'BGL' AND o.key_type = 'component' AND o.key_value = b.component)
SELECT 'S6 bgl_ev x owner_map: ' || team AS claim, count(*) || ' / ' || count(*) FILTER (WHERE is_alert) AS independent,
       count(*) FILTER (WHERE stored <> team) AS rows_where_stored_team_differs
FROM j GROUP BY team ORDER BY count(*) DESC;

-- =============================================================================================
-- S7 (claim 7). Top 6 signatures by 5-min domain episodes: episodes / alert lines / nodes_affected /
--   peak_nodes_per_episode / active_days. No tie at the cut (#6 963, #7 937).
-- =============================================================================================
WITH a AS (
  SELECT "timestamp"::timestamp AS t, node,
         regexp_replace(regexp_replace(content,
           '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig,
         CASE WHEN length(node) - length(replace(node, '-', '')) >= 2
              THEN split_part(node, '-', 1) || '-' || split_part(node, '-', 2) ELSE 'UNKNOWN' END AS mp
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'),
f AS (SELECT *, CASE WHEN lag(t) OVER w IS NULL OR t - lag(t) OVER w > INTERVAL '5 minutes' THEN 1 ELSE 0 END AS st
      FROM a WINDOW w AS (PARTITION BY sig, mp ORDER BY t)),
n AS (SELECT *, sum(st) OVER (PARTITION BY sig, mp ORDER BY t ROWS UNBOUNDED PRECEDING) AS ep FROM f),
e AS (SELECT sig, mp, ep, count(DISTINCT node) AS ep_nodes FROM n GROUP BY sig, mp, ep),
se AS (SELECT sig, count(*) AS eps, max(ep_nodes) AS peak FROM e GROUP BY sig),
sg AS (SELECT sig, count(*) AS lines, count(DISTINCT node) AS nodes, count(DISTINCT CAST(t AS DATE)) AS days FROM a GROUP BY sig),
k AS (SELECT row_number() OVER (ORDER BY eps DESC) AS pos, * FROM se JOIN sg USING (sig)),
s(pos, sig, eps, lines, nodes, peak, days) AS (VALUES
  (1, 'Lustre mount FAILED : bglio{n} : point /p/gb{n}', 3667, 26426, 1024, 8, 12),
  (2, 'ciod: Error reading message prefix on CioStream socket to {n}.{n}.{n}.{n}:{n}, Link has been severed', 3638, 26546, 1024, 8, 35),
  (3, 'rts: kernel terminated for reason {n}', 2641, 18587, 7650, 512, 17),
  (4, 'ciod: Error reading message prefix after LOAD_MESSAGE on CioStream socket to {n}.{n}.{n}.{n}:{n}: Link has been severed', 2282, 15273, 1024, 8, 27),
  (5, 'ciod: Error reading message prefix after LOGIN_MESSAGE on CioStream socket to {n}.{n}.{n}.{n}:{n}: Link has been severed', 1042, 5683, 1024, 8, 10),
  (6, 'rts: kernel terminated for reason {n}rts: bad message header: invalid cpu, type={n}, cpu={n}, index={n}, total={n}', 963, 3334, 1255, 31, 10))
SELECT 'S7 by episodes #' || s.pos || ' ' || left(s.sig, 48) AS claim,
       s.eps || ' / ' || s.lines || ' / ' || s.nodes || ' / ' || s.peak || ' / ' || s.days AS stated,
       k.eps || ' / ' || k.lines || ' / ' || k.nodes || ' / ' || k.peak || ' / ' || k.days || ' [' || left(md5(k.sig), 12) || ']' AS independent,
       k.sig = s.sig AND k.eps = s.eps AND k.lines = s.lines AND k.nodes = s.nodes AND k.peak = s.peak AND k.days = s.days AS match
FROM s LEFT JOIN k USING (pos)
UNION ALL
SELECT 'S7 NOTE #7 episodes (cut margin)', '< 963', eps::VARCHAR, eps < 963 FROM k WHERE pos = 7
ORDER BY 1;

-- =============================================================================================
-- S8 (claim 8). Per team: alert signatures / alert lines / 5-min domain episodes / % of 19250 episodes.
--   Every alert signature has exactly one component, so one team (NOTE row).
-- =============================================================================================
WITH om AS (SELECT key_value, team FROM read_csv('/data/ownership.csv') WHERE dataset = 'BGL' AND key_type = 'component'),
a AS (
  SELECT "timestamp"::timestamp AS t, b.component, coalesce(om.team, 'UNOWNED') AS team,
         regexp_replace(regexp_replace(content,
           '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig,
         CASE WHEN length(node) - length(replace(node, '-', '')) >= 2
              THEN split_part(node, '-', 1) || '-' || split_part(node, '-', 2) ELSE 'UNKNOWN' END AS mp
  FROM read_parquet('/data/loghub/bgl.parquet') b LEFT JOIN om ON om.key_value = b.component WHERE b.label <> '-'),
f AS (SELECT team, sig, CASE WHEN lag(t) OVER w IS NULL OR t - lag(t) OVER w > INTERVAL '5 minutes' THEN 1 ELSE 0 END AS st
      FROM a WINDOW w AS (PARTITION BY sig, mp ORDER BY t)),
r AS (SELECT team, count(DISTINCT sig) AS sigs, count(*) AS lines, sum(st) AS eps FROM f GROUP BY team),
tot AS (SELECT sum(eps) AS te FROM r),
s(team, sigs, lines, eps, pct) AS (VALUES
  ('compute-platform', 65, 284391, 9952, CAST(51.70 AS DOUBLE)),
  ('workload-runtime', 19, 63845, 9240, 48.00),
  ('network-fabric', 10, 206, 42, NULL),
  ('observability', 5, 15, 14, NULL),
  ('storage-platform', 1, 3, 2, NULL))
SELECT 'S8 team ' || s.team || ' sigs / lines / episodes (%)' AS claim,
       s.sigs || ' / ' || s.lines || ' / ' || s.eps || coalesce(' (' || s.pct || ')', '') AS stated,
       r.sigs || ' / ' || r.lines || ' / ' || r.eps || ' (' || round(CAST(r.eps AS DOUBLE) * 100 / tot.te, 2) || ')' AS independent,
       r.sigs = s.sigs AND r.lines = s.lines AND r.eps = s.eps
         AND (s.pct IS NULL OR abs(round(CAST(r.eps AS DOUBLE) * 100 / tot.te, 2) - s.pct) < 1e-9) AS match
FROM s LEFT JOIN r USING (team) CROSS JOIN tot
UNION ALL
SELECT 'S8 teams with alert lines / total episodes', '5 / 19250', count(*) || ' / ' || sum(eps), count(*) = 5 AND sum(eps) = 19250 FROM r
UNION ALL
SELECT 'S8 NOTE signatures with > 1 component or team', '0',
       (SELECT count(*) FROM (SELECT sig FROM a GROUP BY sig HAVING count(DISTINCT component) > 1 OR count(DISTINCT team) > 1) x)::VARCHAR,
       (SELECT count(*) FROM (SELECT sig FROM a GROUP BY sig HAVING count(DISTINCT component) > 1 OR count(DISTINCT team) > 1) x) = 0
ORDER BY 1;

-- =============================================================================================
-- S9 (claim 9). Weekly trend of the top 4 signatures by 5-min domain episodes.
--   Formulation A (raw): Monday weeks as integer week numbers floor((day - 1970-01-05) / 7), dense
--   series from the earliest to the latest episode-start week over ALL alert signatures, week index
--   from 0; slope = regr_slope(incidents, week_index) over all 32 weeks including zero weeks.
--   expected 32 weeks, 2005-05-30 .. 2006-01-02; (active weeks, peak, slope, last_9_weeks):
--   Lustre point (3, 1872, -2.501, 0); ciod CioStream (8, 1110, 14.806, 3638);
--   rts kernel terminated (9, 1707, -4.094, 10); ciod LOAD_MESSAGE (12, 541, 0.137, 175).
-- =============================================================================================
WITH a AS (
  SELECT "timestamp"::timestamp AS t,
         regexp_replace(regexp_replace(content,
           '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig,
         CASE WHEN length(node) - length(replace(node, '-', '')) >= 2
              THEN split_part(node, '-', 1) || '-' || split_part(node, '-', 2) ELSE 'UNKNOWN' END AS mp
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'),
st AS (SELECT sig, t FROM (SELECT sig, t, lag(t) OVER (PARTITION BY sig, mp ORDER BY t) AS p FROM a) x
       WHERE p IS NULL OR t - p > INTERVAL '5 minutes'),
sw AS (SELECT sig, CAST(floor(CAST(CAST(t AS DATE) - DATE '1970-01-05' AS DOUBLE) / 7) AS BIGINT) AS wn FROM st),
b AS (SELECT min(wn) AS w0, max(wn) AS w1 FROM sw),
weeks AS (SELECT g.i AS wi, b.w0 + g.i AS wn FROM b, generate_series(0, b.w1 - b.w0) AS g(i)),
lw AS (SELECT max(wi) AS last_wi FROM weeks),
top AS (SELECT sig, count(*) AS eps FROM sw GROUP BY sig ORDER BY eps DESC LIMIT 4),
cnt AS (SELECT sig, wn, count(*) AS n FROM sw GROUP BY sig, wn),
grid AS (SELECT top.sig, top.eps, weeks.wi, coalesce(cnt.n, 0) AS n
         FROM top CROSS JOIN weeks LEFT JOIN cnt ON cnt.sig = top.sig AND cnt.wn = weeks.wn),
k AS (SELECT sig, eps, count(*) FILTER (WHERE n > 0) AS active, max(n) AS peak, regr_slope(n, wi) AS slope,
             sum(n) FILTER (WHERE wi >= (SELECT last_wi FROM lw) - 8) AS l9,
             sum(n) FILTER (WHERE wi >= (SELECT last_wi FROM lw) - 7) AS l8,
             sum(n) FILTER (WHERE wi >= (SELECT last_wi FROM lw) - 9) AS l10
      FROM grid GROUP BY sig, eps),
s(sig, active, peak, slope, l9) AS (VALUES
  ('Lustre mount FAILED : bglio{n} : point /p/gb{n}', 3, 1872, CAST(-2.501 AS DOUBLE), 0),
  ('ciod: Error reading message prefix on CioStream socket to {n}.{n}.{n}.{n}:{n}, Link has been severed', 8, 1110, 14.806, 3638),
  ('rts: kernel terminated for reason {n}', 9, 1707, -4.094, 10),
  ('ciod: Error reading message prefix after LOAD_MESSAGE on CioStream socket to {n}.{n}.{n}.{n}:{n}: Link has been severed', 12, 541, 0.137, 175))
SELECT 'S9 weeks / first Monday / last Monday' AS claim, '32 / 2005-05-30 / 2006-01-02' AS stated,
       (b.w1 - b.w0 + 1) || ' / ' || (DATE '1970-01-05' + CAST(7 * b.w0 AS INTEGER)) || ' / ' || (DATE '1970-01-05' + CAST(7 * b.w1 AS INTEGER)) AS independent,
       b.w1 - b.w0 + 1 = 32 AND DATE '1970-01-05' + CAST(7 * b.w0 AS INTEGER) = DATE '2005-05-30'
         AND DATE '1970-01-05' + CAST(7 * b.w1 AS INTEGER) = DATE '2006-01-02' AS match FROM b
UNION ALL
SELECT 'S9 trend ' || left(s.sig, 48) || ' (active, peak, slope, last_9)',
       s.active || ', ' || s.peak || ', ' || s.slope || ', ' || s.l9,
       k.active || ', ' || k.peak || ', ' || round(k.slope, 3) || ', ' || k.l9 || '  [eps ' || k.eps || '; last_8 ' || k.l8 || ', last_10 ' || k.l10 || ']',
       k.active = s.active AND k.peak = s.peak AND abs(round(k.slope, 3) - s.slope) < 1e-9 AND k.l9 = s.l9
FROM s LEFT JOIN k USING (sig)
ORDER BY 1;

-- S9 second source: bgl_ev, date_trunc('week', ...) buckets, a timestamp generate_series, ROWS-frame
-- previous ts, and the last-9-weeks window as wk >= last_week - INTERVAL '8 weeks'
WITH a AS (SELECT ts AS t,
                  regexp_replace(regexp_replace(content, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
                                                '{uuid}', 'g'), '\d+', '{n}', 'g') AS sig,
                  CASE WHEN node ~ '^[^-]*-[^-]*-' THEN regexp_extract(node, '^([^-]*-[^-]*)-', 1) ELSE 'UNKNOWN' END AS mp
           FROM bgl_ev WHERE alert_category <> '-'),
st AS (SELECT sig, t FROM (SELECT sig, t, max(t) OVER (PARTITION BY sig, mp ORDER BY t ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING) AS p FROM a) x
       WHERE p IS NULL OR extract(epoch FROM t) - extract(epoch FROM p) > 300),
sw AS (SELECT sig, CAST(date_trunc('week', CAST(t AS TIMESTAMPTZ)) AS TIMESTAMP) AS wk FROM st),
weeks AS (SELECT wk, row_number() OVER (ORDER BY wk) - 1 AS wi
          FROM generate_series((SELECT min(wk) FROM sw), (SELECT max(wk) FROM sw), INTERVAL '7 days') AS g(wk)),
top AS (SELECT sig, count(*) AS eps FROM sw GROUP BY sig ORDER BY eps DESC LIMIT 4),
cnt AS (SELECT sig, wk, count(*) AS n FROM sw GROUP BY sig, wk),
grid AS (SELECT top.sig, top.eps, weeks.wi, weeks.wk, coalesce(cnt.n, 0) AS n
         FROM top CROSS JOIN weeks LEFT JOIN cnt ON cnt.sig = top.sig AND cnt.wk = weeks.wk)
SELECT 'S9 bgl_ev date_trunc: ' || left(sig, 40) AS claim, count(*) AS weeks, min(wk)::DATE AS first_week, max(wk)::DATE AS last_week,
       count(*) FILTER (WHERE n > 0) AS active, max(n) AS peak, round(regr_slope(n, wi), 3) AS slope,
       sum(n) FILTER (WHERE wk >= (SELECT max(wk) FROM weeks) - INTERVAL '8 weeks') AS last_9
FROM grid GROUP BY sig, eps ORDER BY eps DESC;

-- =============================================================================================
-- S10 (claim 10). Alert lines per 5-min domain incident.   expected 348460 / 19250 = 18.1
-- =============================================================================================
WITH a AS (
  SELECT "timestamp"::timestamp AS t,
         regexp_replace(regexp_replace(content,
           '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig,
         CASE WHEN length(node) - length(replace(node, '-', '')) >= 2
              THEN split_part(node, '-', 1) || '-' || split_part(node, '-', 2) ELSE 'UNKNOWN' END AS mp
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'),
g AS (SELECT t, lag(t) OVER (PARTITION BY sig, mp ORDER BY t) AS p FROM a),
c AS (SELECT count(*) AS lines, count(*) FILTER (WHERE p IS NULL OR t - p > INTERVAL '5 minutes') AS inc FROM g)
SELECT 'S10 alert lines / incidents = lines per incident' AS claim, '348460 / 19250 = 18.1' AS stated,
       lines || ' / ' || inc || ' = ' || round(CAST(lines AS DOUBLE) / inc, 4) AS independent,
       lines = 348460 AND inc = 19250 AND abs(round(CAST(lines AS DOUBLE) / inc, 1) - 18.1) < 1e-9 AS match FROM c;

-- =============================================================================================
-- S11 (claim 11). Manager risk order over the 100 alert signatures:
--   order by dense_rank(nodes_affected DESC) + dense_rank(active_days DESC), then the nodes rank, then
--   signature_id. "position by lines" = rank(alert lines DESC) (no ties among the rows shown).
--   expected (category, nodes, days, rank sum, lines position):
--   1 rts panic KERNRTSP (3394, 124, 4, 10); 2 rts kernel terminated KERNTERM (7650, 17, 10, 5);
--   3 ciod CioStream APPSEV (1024, 35, 12, 3); 4 ciod LOAD_MESSAGE APPSEV (1024, 27, 13, 6);
--   5 Lustre block_id KERNMNTF (1024, 16, 16, 9); 12 data TLB error interrupt (541, 11, 23, 1).
--   Ties: rank sums 4, 10, 12, 13, 16 and 23 are unique; ties exist at 17 (positions 6-7) and 18
--   (positions 8-9), above position 12, so no stated position depends on the tie-break (NOTE row).
-- =============================================================================================
WITH a AS (
  SELECT "timestamp"::timestamp AS t, node, label,
         regexp_replace(regexp_replace(content,
           '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'),
sg AS (SELECT sig, left(md5(sig), 12) AS sid, min(label) AS cat, count(DISTINCT label) AS ncat, count(*) AS lines,
              count(DISTINCT node) AS nodes, count(DISTINCT CAST(t AS DATE)) AS days FROM a GROUP BY sig),
r AS (SELECT *, dense_rank() OVER (ORDER BY nodes DESC) AS rn, dense_rank() OVER (ORDER BY days DESC) AS rd,
             rank() OVER (ORDER BY lines DESC) AS lpos FROM sg),
o AS (SELECT *, rn + rd AS rsum, row_number() OVER (ORDER BY rn + rd, rn, sid) AS pos,
             rank() OVER (ORDER BY rn + rd) AS pos_sum_only FROM r),
s(pos, sig, cat, nodes, days, rsum, lpos) AS (VALUES
  (1, 'rts panic! - stopping execution', 'KERNRTSP', 3394, 124, 4, 10),
  (2, 'rts: kernel terminated for reason {n}', 'KERNTERM', 7650, 17, 10, 5),
  (3, 'ciod: Error reading message prefix on CioStream socket to {n}.{n}.{n}.{n}:{n}, Link has been severed', 'APPSEV', 1024, 35, 12, 3),
  (4, 'ciod: Error reading message prefix after LOAD_MESSAGE on CioStream socket to {n}.{n}.{n}.{n}:{n}: Link has been severed', 'APPSEV', 1024, 27, 13, 6),
  (5, 'Lustre mount FAILED : bglio{n} : block_id : location', 'KERNMNTF', 1024, 16, 16, 9),
  (12, 'data TLB error interrupt', 'KERNDTLB', 541, 11, 23, 1))
SELECT 'S11 risk #' || lpad(s.pos::VARCHAR, 2, '0') || ' ' || left(s.sig, 44) AS claim,
       s.cat || ' (' || s.nodes || ', ' || s.days || ', ' || s.rsum || ', lines #' || s.lpos || ')' AS stated,
       o.cat || ' (' || o.nodes || ', ' || o.days || ', ' || o.rsum || ', lines #' || o.lpos || ')  [' || o.sid
         || '; ranks ' || o.rn || '+' || o.rd || '; pos by sum only ' || o.pos_sum_only || ']' AS independent,
       o.sig = s.sig AND o.cat = s.cat AND o.ncat = 1 AND o.nodes = s.nodes AND o.days = s.days AND o.rsum = s.rsum
         AND o.lpos = s.lpos AND o.pos_sum_only = s.pos AS match
FROM s LEFT JOIN o USING (pos)
UNION ALL
SELECT 'S11 NOTE rank sums shared by > 1 signature among positions 1-12', '-',
       string_agg(rsum || ' (pos ' || pmin || '-' || pmax || ')', ', ' ORDER BY rsum), NULL
FROM (SELECT rsum, min(pos) AS pmin, max(pos) AS pmax FROM o WHERE pos <= 12 GROUP BY rsum HAVING count(*) > 1) t
UNION ALL
SELECT 'S11 signatures ranked', '100', count(*)::VARCHAR, count(*) = 100 FROM o
ORDER BY 1;

-- =============================================================================================
-- S12 (claim 12). OpenStack lines, distinct non-empty instance IDs, first and last ts.
--   expected 207812, 2069, 2017-05-14 19:39:01.445 .. 2017-05-17 12:02:35.32.
--   os_ev stores 'NONE' as the empty-instance sentinel, so it is excluded there.
-- =============================================================================================
WITH r AS (SELECT count(*) AS n, count(DISTINCT instance_id) FILTER (WHERE instance_id IS NOT NULL AND instance_id <> '') AS inst,
                  min("timestamp"::timestamp) AS t0, max("timestamp"::timestamp) AS t1
           FROM read_parquet('/data/loghub/openstack.parquet')),
e AS (SELECT count(*) AS n, count(DISTINCT instance_id) FILTER (WHERE instance_id <> 'NONE' AND instance_id <> '') AS inst,
             min(ts) AS t0, max(ts) AS t1 FROM os_ev)
SELECT 'S12 OpenStack lines (parquet | os_ev)' AS claim, '207812' AS stated, r.n || ' | ' || e.n AS independent,
       r.n = 207812 AND e.n = 207812 AS match FROM r, e
UNION ALL SELECT 'S12 distinct instance IDs, non-empty (parquet | os_ev)', '2069', r.inst || ' | ' || e.inst,
       r.inst = 2069 AND e.inst = 2069 FROM r, e
UNION ALL SELECT 'S12 first ts (parquet | os_ev)', '2017-05-14 19:39:01.445', r.t0 || ' | ' || e.t0,
       r.t0 = TIMESTAMP '2017-05-14 19:39:01.445' AND e.t0 = r.t0 FROM r, e
UNION ALL SELECT 'S12 last ts (parquet | os_ev)', '2017-05-17 12:02:35.32', r.t1 || ' | ' || e.t1,
       r.t1 = TIMESTAMP '2017-05-17 12:02:35.32' AND e.t1 = r.t1 FROM r, e;

-- =============================================================================================
-- S13 (claim 13). API latency p50 / p99, quantile_cont (linear), rows with a parsed latency_s.
--   expected abnormal file 0.2594 / 0.5092; normal1 + normal2 together 0.2596 / 0.5149 (4 dp).
--   percentile_cont shown; quantile_disc as a NOTE (it would round abnormal p99 to 0.5093).
-- =============================================================================================
WITH l AS (SELECT CASE WHEN origin_file = 'openstack_abnormal.log' THEN 'abnormal' ELSE 'normal1+normal2' END AS grp, latency_s
           FROM read_parquet('/data/loghub/openstack.parquet') WHERE latency_s IS NOT NULL),
q AS (SELECT grp, count(*) AS calls, quantile_cont(latency_s, 0.5) AS p50, quantile_cont(latency_s, 0.99) AS p99,
             percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_s) AS pc50, percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_s) AS pc99,
             quantile_disc(latency_s, 0.5) AS d50, quantile_disc(latency_s, 0.99) AS d99 FROM l GROUP BY grp),
s(grp, p50, p99) AS (VALUES ('abnormal', CAST(0.2594 AS DOUBLE), CAST(0.5092 AS DOUBLE)), ('normal1+normal2', 0.2596, 0.5149))
SELECT 'S13 latency ' || s.grp || ' p50 / p99' AS claim, s.p50 || ' / ' || s.p99 AS stated,
       round(q.p50, 6) || ' / ' || round(q.p99, 6) || '  [' || q.calls || ' calls; pct_cont ' || round(q.pc50, 6) || ' / ' || round(q.pc99, 6)
         || '; NOTE disc ' || q.d50 || ' / ' || q.d99 || ']' AS independent,
       abs(round(q.p50, 4) - s.p50) < 1e-9 AND abs(round(q.p99, 4) - s.p99) < 1e-9
         AND abs(q.pc50 - q.p50) <= 1e-6 * q.p50 AND abs(q.pc99 - q.p99) <= 1e-6 * q.p99 AS match
FROM s LEFT JOIN q USING (grp) ORDER BY 1;

-- S13 second source: os_ev
SELECT 'S13 os_ev latency ' || CASE WHEN source_file = 'openstack_abnormal.log' THEN 'abnormal' ELSE 'normal1+normal2' END AS claim,
       count(latency_s) AS calls, round(quantile_cont(latency_s, 0.5), 4) AS p50, round(quantile_cont(latency_s, 0.99), 4) AS p99
FROM os_ev WHERE latency_s IS NOT NULL GROUP BY 1 ORDER BY 1;

-- =============================================================================================
-- S14 (claim 14). Lines above INFO per (logger, level), incidents at a 5-min gap (new when the gap to
--   the previous line of the same logger + level is > 300 s), and logger-first ownership
--   (data/ownership.csv: logger row, else service row, else 'UNOWNED').
--   expected nova.compute.manager WARNING 45 / 45; nova.virt.libvirt.driver WARNING 12 / 10;
--   teams auth_token identity, periodic_task platform-services, imagecache image-service,
--   compute.manager and libvirt.driver compute-platform.
--   Boundary: compute.manager's smallest gap is 614.056 s, so 45 holds for any threshold < 614 s;
--   libvirt.driver's largest in-incident gap is 123.971 s and smallest split 909.696 s (NOTE rows).
-- =============================================================================================
WITH p AS (SELECT logger, level, extract(epoch FROM "timestamp"::timestamp) AS e
           FROM read_parquet('/data/loghub/openstack.parquet') WHERE level <> 'INFO'),
g AS (SELECT logger, level, e - lag(e) OVER (PARTITION BY logger, level ORDER BY e) AS gap FROM p),
c AS (SELECT logger, level, count(*) AS lines, count(*) FILTER (WHERE gap IS NULL OR gap > 300) AS inc,
             min(gap) FILTER (WHERE gap > 300) AS min_split, max(gap) FILTER (WHERE gap <= 300) AS max_in
      FROM g GROUP BY logger, level),
s(logger, level, lines, inc) AS (VALUES ('nova.compute.manager', 'WARNING', 45, 45), ('nova.virt.libvirt.driver', 'WARNING', 12, 10))
SELECT 'S14 ' || s.logger || ' ' || s.level || ' lines / incidents' AS claim, s.lines || ' / ' || s.inc AS stated,
       c.lines || ' / ' || c.inc || '  [min split gap ' || round(c.min_split, 3) || ' s; max in-incident gap '
         || coalesce(round(c.max_in, 3)::VARCHAR || ' s', 'none') || ']' AS independent,
       c.lines = s.lines AND c.inc = s.inc AS match
FROM s LEFT JOIN c USING (logger, level)
ORDER BY 1;

WITH m AS (SELECT key_type, key_value, team FROM read_csv('/data/ownership.csv') WHERE dataset = 'OpenStack'),
r AS (SELECT logger, service, count(*) AS n FROM read_parquet('/data/loghub/openstack.parquet') WHERE level <> 'INFO' GROUP BY logger, service),
t AS (SELECT r.logger, string_agg(DISTINCT coalesce(ml.team, ms.team, 'UNOWNED'), ',') AS teams
      FROM r LEFT JOIN m ml ON ml.key_type = 'logger' AND ml.key_value = r.logger
             LEFT JOIN m ms ON ms.key_type = 'service' AND ms.key_value = r.service GROUP BY r.logger),
ev AS (SELECT logger, string_agg(DISTINCT team, ',') AS teams FROM os_ev WHERE level <> 'INFO' GROUP BY logger),
s(logger, team) AS (VALUES ('keystonemiddleware.auth_token', 'identity'), ('oslo_service.periodic_task', 'platform-services'),
                           ('nova.virt.libvirt.imagecache', 'image-service'), ('nova.compute.manager', 'compute-platform'),
                           ('nova.virt.libvirt.driver', 'compute-platform'))
SELECT 'S14 owner of ' || s.logger AS claim, s.team AS stated, t.teams || '  (os_ev.team ' || ev.teams || ')' AS independent,
       t.teams = s.team AND ev.teams = s.team AS match
FROM s LEFT JOIN t USING (logger) LEFT JOIN ev USING (logger)
UNION ALL
SELECT 'S14 loggers with lines above INFO', '5', count(*)::VARCHAR, count(*) = 5 FROM t
ORDER BY 1;

-- =============================================================================================
-- S15 (claim 15). Spawn time per file group (N in '... Took N seconds to spawn the instance on the
--   hypervisor.'), and the image phase ('[instance: <id>] Creating image' -> '[instance: <id>] VM
--   Started (Lifecycle Event)'), per instance, grouped by is_abnormal_file. No instance spans the two
--   groups (one instance, 0f079bdd-..., spans normal1 and normal2, same group).
--   expected spawn abnormal 197, p50 19.79, p95 21.1, max 50.72; normal 1869, p50 19.74, p95 20.98,
--   max 22.56; image p50 13.08 both, max 44.454 abnormal, 15.298 normal.
--   Percentiles: quantile_cont (linear); quantile_disc would give abnormal spawn p95 21.19 (NOTE).
-- =============================================================================================
WITH r AS (SELECT instance_id AS iid, is_abnormal_file AS ab, "timestamp"::timestamp AS t, message AS m
           FROM read_parquet('/data/loghub/openstack.parquet') WHERE instance_id IS NOT NULL AND instance_id <> ''),
pi AS (SELECT iid, ab,
              count(nullif(regexp_extract(m, 'Took ([0-9]+(\.[0-9]+)?) seconds to spawn the instance on the hypervisor\.$', 1), '')) AS n_sp,
              max(CAST(nullif(regexp_extract(m, 'Took ([0-9]+(\.[0-9]+)?) seconds to spawn the instance on the hypervisor\.$', 1), '') AS DOUBLE)) AS spawn_s,
              min(t) FILTER (WHERE m = '[instance: ' || iid || '] Creating image') AS t_ci,
              min(t) FILTER (WHERE m = '[instance: ' || iid || '] VM Started (Lifecycle Event)') AS t_vs
       FROM r GROUP BY iid, ab),
d AS (SELECT CASE WHEN ab THEN 'abnormal' ELSE 'normal' END AS grp, iid, n_sp, spawn_s,
             extract(epoch FROM t_vs) - extract(epoch FROM t_ci) AS image_s FROM pi),
q AS (SELECT grp, count(spawn_s) AS n, max(n_sp) AS max_spawn_lines, quantile_cont(spawn_s, 0.5) AS p50, quantile_cont(spawn_s, 0.95) AS p95,
             percentile_cont(0.95) WITHIN GROUP (ORDER BY spawn_s) AS pc95, quantile_disc(spawn_s, 0.95) AS d95, max(spawn_s) AS mx,
             count(image_s) FILTER (WHERE spawn_s IS NOT NULL) AS n_img, quantile_cont(image_s, 0.5) FILTER (WHERE spawn_s IS NOT NULL) AS i50,
             max(image_s) FILTER (WHERE spawn_s IS NOT NULL) AS imx
      FROM d GROUP BY grp),
s(grp, n, p50, p95, mx, i50, imx) AS (VALUES
  ('abnormal', 197, CAST(19.79 AS DOUBLE), CAST(21.1 AS DOUBLE), CAST(50.72 AS DOUBLE), CAST(13.08 AS DOUBLE), CAST(44.454 AS DOUBLE)),
  ('normal', 1869, 19.74, 20.98, 22.56, 13.08, 15.298))
SELECT 'S15 spawn ' || s.grp || ' instances / p50 / p95 / max' AS claim,
       s.n || ' / ' || s.p50 || ' / ' || s.p95 || ' / ' || s.mx AS stated,
       q.n || ' / ' || round(q.p50, 4) || ' / ' || round(q.p95, 4) || ' / ' || q.mx || '  [pct_cont p95 ' || round(q.pc95, 4)
         || '; NOTE disc p95 ' || q.d95 || '; spawn lines per instance <= ' || q.max_spawn_lines || ']' AS independent,
       q.n = s.n AND abs(round(q.p50, 2) - s.p50) < 1e-9 AND abs(round(q.p95, 2) - s.p95) < 1e-9 AND abs(q.mx - s.mx) < 1e-9
         AND abs(q.pc95 - q.p95) <= 1e-6 * q.p95 AND q.max_spawn_lines = 1 AS match
FROM s LEFT JOIN q USING (grp)
UNION ALL
SELECT 'S15 image ' || s.grp || ' p50 / max (spawned instances with both lines)',
       s.i50 || ' / ' || s.imx,
       round(q.i50, 4) || ' / ' || round(q.imx, 3) || '  [' || q.n_img || ' instances]',
       abs(round(q.i50, 2) - s.i50) < 1e-9 AND abs(round(q.imx, 3) - s.imx) < 1e-9
FROM s LEFT JOIN q USING (grp)
UNION ALL
SELECT 'S15 instances in both file groups', '0',
       (SELECT count(*) FROM (SELECT iid FROM pi GROUP BY iid HAVING count(*) > 1) x)::VARCHAR,
       (SELECT count(*) FROM (SELECT iid FROM pi GROUP BY iid HAVING count(*) > 1) x) = 0
ORDER BY 1;

-- S15 second source: os_ev.spawn_s (the derive step's extraction), grouped by source file
SELECT 'S15 os_ev spawn ' || CASE WHEN source_file = 'openstack_abnormal.log' THEN 'abnormal' ELSE 'normal' END AS claim,
       count(*) AS instances, count(DISTINCT instance_id) AS distinct_ids, round(quantile_cont(spawn_s, 0.5), 4) AS p50,
       round(quantile_cont(spawn_s, 0.95), 4) AS p95, max(spawn_s) AS max_s
FROM os_ev WHERE spawn_s IS NOT NULL GROUP BY 1 ORDER BY 1;
