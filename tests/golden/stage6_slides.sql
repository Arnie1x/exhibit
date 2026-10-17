-- tests/golden/stage6_slides.sql
-- Independent re-derivation of every corpus figure on the slides (docs/slides.md), written by the
-- sql-verifier subagent on 17 Oct without the views (raw Parquet, or bgl_ev / os_ev; views only
-- where the claim is about a view). All 17 claim groups matched; the expected values sit in each
-- section's header. Read-only. Section 17 reads Parquet FOOTER metadata only, with the external
-- file cache off: never point a data-page read at the remote file (docs/capabilities.md §11).
--
-- Run: psql -h 127.0.0.1 -p 7890 -U postgres -P pager=off < tests/golden/stage6_slides.sql

-- ==== 1-2 burst 152,183 on R30-M0-N9-C:J16-U01 (17:17:44 to 23:39:32, 43.67%); 2005-06-14: 49,154 lines on 22,529 nodes
\echo '=== c1'
-- Claim 1: raw parquet
WITH r AS (
  SELECT node, label, "timestamp"::timestamp AS t
  FROM read_parquet('/data/loghub/bgl.parquet')
)
SELECT count(*) FILTER (WHERE label <> '-') AS alerts_total,
       count(*) FILTER (WHERE label <> '-' AND node = 'R30-M0-N9-C:J16-U01' AND t >= TIMESTAMP '2005-06-11' AND t < TIMESTAMP '2005-06-12') AS burst,
       min(t) FILTER (WHERE label <> '-' AND node = 'R30-M0-N9-C:J16-U01' AND t >= TIMESTAMP '2005-06-11' AND t < TIMESTAMP '2005-06-12') AS first_t,
       max(t) FILTER (WHERE label <> '-' AND node = 'R30-M0-N9-C:J16-U01' AND t >= TIMESTAMP '2005-06-11' AND t < TIMESTAMP '2005-06-12') AS last_t,
       count(DISTINCT node) FILTER (WHERE label <> '-' AND t >= TIMESTAMP '2005-06-11' AND t < TIMESTAMP '2005-06-12') AS nodes_0611,
       count(*) FILTER (WHERE label <> '-' AND t >= TIMESTAMP '2005-06-14' AND t < TIMESTAMP '2005-06-15') AS lines_0614,
       count(DISTINCT node) FILTER (WHERE label <> '-' AND t >= TIMESTAMP '2005-06-14' AND t < TIMESTAMP '2005-06-15') AS nodes_0614
FROM r;
-- same on bgl_ev
SELECT count(*) FILTER (WHERE is_alert) AS alerts_total,
       count(*) FILTER (WHERE is_alert AND node='R30-M0-N9-C:J16-U01' AND ts::date = DATE '2005-06-11') AS burst,
       min(ts) FILTER (WHERE is_alert AND node='R30-M0-N9-C:J16-U01' AND ts::date = DATE '2005-06-11') AS f,
       max(ts) FILTER (WHERE is_alert AND node='R30-M0-N9-C:J16-U01' AND ts::date = DATE '2005-06-11') AS l,
       count(*) FILTER (WHERE is_alert AND ts::date = DATE '2005-06-14') AS l14,
       count(DISTINCT node) FILTER (WHERE is_alert AND ts::date = DATE '2005-06-14') AS n14,
       count(*) FILTER (WHERE is_alert <> (alert_category <> '-')) AS alert_flag_mismatch
FROM bgl_ev;
SELECT round(152183::DOUBLE/348460*100, 4) AS pct, TIMESTAMP '2005-06-11 23:39:32.9' - TIMESTAMP '2005-06-11 17:17:44.6' AS span;


-- ==== 3 alert lines 348,460 -> 19,250 incidents (signature x midplane, 5 min) -> 1,377 (signature)
\echo '=== c3'
-- Claim 3 from raw parquet, own midplane derivation
WITH a AS (
  SELECT "timestamp"::timestamp AS t, node,
         coalesce(nullif(regexp_extract(node, '^(R[0-9]+-M[0-9]+)', 1), ''), 'UNKNOWN') AS mp,
         regexp_replace(regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'), '[0-9]+', '{n}', 'g') AS sig
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'
), g AS (
  SELECT sig, mp, t,
         lag(t) OVER (PARTITION BY sig, mp ORDER BY t) AS p_mp,
         lag(t) OVER (PARTITION BY sig ORDER BY t) AS p_sig
  FROM a
)
SELECT count(*) AS lines,
       count(DISTINCT sig) AS sigs,
       count(DISTINCT mp) AS mps,
       count(*) FILTER (WHERE p_mp IS NULL OR t - p_mp > INTERVAL '5 minutes') AS inc_sig_mp,
       count(*) FILTER (WHERE p_sig IS NULL OR t - p_sig > INTERVAL '5 minutes') AS inc_sig,
       count(*) FILTER (WHERE p_mp IS NULL OR t - p_mp >= INTERVAL '5 minutes') AS inc_sig_mp_ge,
       count(*) FILTER (WHERE p_sig IS NULL OR t - p_sig >= INTERVAL '5 minutes') AS inc_sig_ge
FROM g;
-- same on bgl_ev's midplane column
WITH a AS (
  SELECT ts AS t, midplane AS mp,
         regexp_replace(regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'), '[0-9]+', '{n}', 'g') AS sig
  FROM bgl_ev WHERE is_alert
), g AS (
  SELECT t, lag(t) OVER (PARTITION BY sig, mp ORDER BY t) AS p FROM a
)
SELECT count(*) FILTER (WHERE p IS NULL OR epoch(t) - epoch(p) > 300) AS inc_sig_mp_bglev FROM g;


-- ==== 4 DTLB 152,734 lines, 117 incidents, 99.64% one node; deepest R30-M0 152,182 lines, 1 node, 6:21:47.98
\echo '=== c4'
WITH a AS (
  SELECT "timestamp"::timestamp AS t, node, label,
         coalesce(nullif(regexp_extract(node, '^(R[0-9]+-M[0-9]+)', 1), ''), 'UNKNOWN') AS mp,
         regexp_replace(regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'), '[0-9]+', '{n}', 'g') AS sig
  FROM read_parquet('/data/loghub/bgl.parquet')
), d AS (SELECT * FROM a WHERE sig = 'data TLB error interrupt')
SELECT count(*) AS all_lines, count(*) FILTER (WHERE label <> '-') AS alert_lines,
       count(DISTINCT node) FILTER (WHERE label <> '-') AS nodes,
       (SELECT count(*) FROM d WHERE label <> '-' AND node = (SELECT node FROM d WHERE label <> '-' GROUP BY node ORDER BY count(*) DESC LIMIT 1)) AS top_node_lines,
       (SELECT node FROM d WHERE label <> '-' GROUP BY node ORDER BY count(*) DESC LIMIT 1) AS top_node
FROM d;
WITH a AS (
  SELECT "timestamp"::timestamp AS t, node,
         coalesce(nullif(regexp_extract(node, '^(R[0-9]+-M[0-9]+)', 1), ''), 'UNKNOWN') AS mp,
         regexp_replace(regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'), '[0-9]+', '{n}', 'g') AS sig
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'
), d AS (SELECT * FROM a WHERE sig = 'data TLB error interrupt'),
f AS (SELECT *, CASE WHEN lag(t) OVER (PARTITION BY mp ORDER BY t) IS NULL OR t - lag(t) OVER (PARTITION BY mp ORDER BY t) > INTERVAL '5 minutes' THEN 1 ELSE 0 END AS s FROM d),
e AS (SELECT *, sum(s) OVER (PARTITION BY mp ORDER BY t ROWS UNBOUNDED PRECEDING) AS eid FROM f),
inc AS (SELECT mp, eid, count(*) AS lines, count(DISTINCT node) AS nodes, min(t) AS st, max(t) AS en, max(t)-min(t) AS span FROM e GROUP BY mp, eid)
SELECT (SELECT count(*) FROM inc) AS incidents, mp, lines, nodes, st, en, span FROM inc ORDER BY lines DESC LIMIT 2;
SELECT round(152182::DOUBLE/152734*100, 4) AS pct;


-- ==== 5 Lustre 3,667 and ciod 'Link has been severed' 3,638 incidents, max 8 nodes in one
\echo '=== c5'
WITH a AS (
  SELECT "timestamp"::timestamp AS t, node,
         coalesce(nullif(regexp_extract(node, '^(R[0-9]+-M[0-9]+)', 1), ''), 'UNKNOWN') AS mp,
         regexp_replace(regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'), '[0-9]+', '{n}', 'g') AS sig
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'
), d AS (
  SELECT * FROM a WHERE sig = 'Lustre mount FAILED : bglio{n} : point /p/gb{n}'
     OR left(sig, length('ciod: Error reading message prefix on CioStream socket to')) = 'ciod: Error reading message prefix on CioStream socket to'
),
f AS (SELECT *, CASE WHEN lag(t) OVER (PARTITION BY sig, mp ORDER BY t) IS NULL OR t - lag(t) OVER (PARTITION BY sig, mp ORDER BY t) > INTERVAL '5 minutes' THEN 1 ELSE 0 END AS s FROM d),
e AS (SELECT *, sum(s) OVER (PARTITION BY sig, mp ORDER BY t ROWS UNBOUNDED PRECEDING) AS eid FROM f),
inc AS (SELECT sig, mp, eid, count(*) AS lines, count(DISTINCT node) AS nodes FROM e GROUP BY sig, mp, eid)
SELECT sig, count(*) AS incidents, sum(lines) AS lines, max(nodes) AS max_nodes_per_incident FROM inc GROUP BY sig ORDER BY 2 DESC;


-- ==== 6-7 rts panic 3,394 nodes / 124 days, position 1; DTLB blast radius 12, persistence 11, sum 23, position 12
\echo '=== c7'
WITH a AS (
  SELECT "timestamp"::timestamp AS t, node,
         regexp_replace(regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'), '[0-9]+', '{n}', 'g') AS sig
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'
), s AS (
  SELECT sig, count(*) AS lines, count(DISTINCT node) AS nodes, count(DISTINCT CAST(t AS DATE)) AS days FROM a GROUP BY sig
), r AS (
  SELECT *, dense_rank() OVER (ORDER BY nodes DESC) AS br, dense_rank() OVER (ORDER BY days DESC) AS pr, left(md5(sig),12) AS sid FROM s
), o AS (
  SELECT *, br+pr AS rs, row_number() OVER (ORDER BY br+pr, br, sid) AS pos FROM r
)
SELECT (SELECT count(*) FROM s) AS n_sigs, pos, sig, lines, nodes, days, br, pr, rs, sid FROM o
WHERE pos <= 13 OR sig IN ('data TLB error interrupt','rts panic! - stopping execution') ORDER BY pos;


-- ==== 8 compute-platform 4,325,112 lines (91.1%), 284,391 alert lines (81.6%), 9,952 incidents (51.7%); workload-runtime 9,240 (48.0%)
\echo '=== c8'
SELECT team, count(*) AS lines, round(count(*)::DOUBLE/sum(count(*)) OVER ()*100, 2) AS pct,
       count(*) FILTER (WHERE is_alert) AS alerts, round(count(*) FILTER (WHERE is_alert)::DOUBLE/sum(count(*) FILTER (WHERE is_alert)) OVER ()*100, 2) AS apct
FROM bgl_ev GROUP BY team ORDER BY lines DESC;
WITH a AS (
  SELECT ts AS t, midplane AS mp, team, node,
         regexp_replace(regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'), '[0-9]+', '{n}', 'g') AS sig
  FROM bgl_ev WHERE is_alert
), f AS (SELECT *, CASE WHEN lag(t) OVER (PARTITION BY sig, mp ORDER BY t) IS NULL OR t - lag(t) OVER (PARTITION BY sig, mp ORDER BY t) > INTERVAL '5 minutes' THEN 1 ELSE 0 END AS s FROM a),
e AS (SELECT *, sum(s) OVER (PARTITION BY sig, mp ORDER BY t ROWS UNBOUNDED PRECEDING) AS eid FROM f),
inc AS (SELECT sig, mp, eid, min(team) AS team, count(DISTINCT team) AS nteams FROM e GROUP BY sig, mp, eid)
SELECT team, count(*) AS incidents, round(count(*)::DOUBLE/sum(count(*)) OVER ()*100, 2) AS pct, max(nteams) AS max_teams_in_incident FROM inc GROUP BY team ORDER BY 2 DESC;


-- ==== 9 ciod 3,638 incidents all in the last 9 weeks, slope 14.81; Lustre 3 weeks, none in the last 9
\echo '=== c9'
WITH a AS (
  SELECT "timestamp"::timestamp AS t,
         coalesce(nullif(regexp_extract(node, '^(R[0-9]+-M[0-9]+)', 1), ''), 'UNKNOWN') AS mp,
         regexp_replace(regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'), '[0-9]+', '{n}', 'g') AS sig
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'
), d AS (
  SELECT * FROM a WHERE sig IN ('Lustre mount FAILED : bglio{n} : point /p/gb{n}',
     'ciod: Error reading message prefix on CioStream socket to {n}.{n}.{n}.{n}:{n}, Link has been severed')
), f AS (SELECT *, lag(t) OVER (PARTITION BY sig, mp ORDER BY t) AS p FROM d),
starts AS (SELECT sig, CAST(date_trunc('week', t::timestamptz) AS DATE) AS wk FROM f WHERE p IS NULL OR t - p > INTERVAL '5 minutes'),
bounds AS (SELECT CAST(date_trunc('week', min("timestamp"::timestamp)::timestamptz) AS DATE) AS w0, CAST(date_trunc('week', max("timestamp"::timestamp)::timestamptz) AS DATE) AS wl FROM read_parquet('/data/loghub/bgl.parquet')),
weeks AS (SELECT CAST(w AS DATE) AS wk, row_number() OVER (ORDER BY w) - 1 AS idx FROM bounds, generate_series(CAST(w0 AS TIMESTAMP), CAST(wl AS TIMESTAMP), INTERVAL '7 days') g(w)),
grid AS (SELECT s.sig, w.wk, w.idx, (SELECT count(*) FROM starts x WHERE x.sig = s.sig AND x.wk = w.wk) AS n
         FROM (SELECT DISTINCT sig FROM starts) s CROSS JOIN weeks w)
SELECT left(sig, 30) AS sig, (SELECT count(*) FROM weeks) AS n_weeks, (SELECT min(wk) FROM weeks) AS w0, (SELECT max(wk) FROM weeks) AS wl,
       sum(n) AS incidents, sum(n) FILTER (WHERE idx >= 23) AS last9, sum(n) FILTER (WHERE idx >= 24) AS last8,
       count(*) FILTER (WHERE n > 0) AS active_weeks, max(n) AS peak, regr_slope(n, idx) AS slope, min(wk) FILTER (WHERE n>0) AS first_wk
FROM grid GROUP BY sig;


-- ==== 10 OpenStack: 188 ERROR+CRITICAL; 184 = 8 records = 8 incidents; auth_token 2+2+2 = 6 lines, 2 incidents; 3,059 warnings, 3 incidents; owners
\echo '=== c10'
-- raw parquet
WITH o AS (SELECT origin_file AS f, pid, "timestamp"::timestamp AS t, logger, level, message FROM read_parquet('/data/loghub/openstack.parquet'))
SELECT count(*) FILTER (WHERE level IN ('ERROR','CRITICAL')) AS err_crit,
       count(*) FILTER (WHERE level='ERROR' AND logger='oslo_service.periodic_task') AS pt_err,
       count(DISTINCT (f, pid, t, logger, level)) FILTER (WHERE level='ERROR' AND logger='oslo_service.periodic_task') AS pt_records,
       count(*) FILTER (WHERE logger='keystonemiddleware.auth_token' AND level='ERROR') AS ks_err,
       count(*) FILTER (WHERE logger='keystonemiddleware.auth_token' AND level='CRITICAL') AS ks_crit,
       count(*) FILTER (WHERE logger='keystonemiddleware.auth_token' AND level='WARNING') AS ks_warn,
       count(*) FILTER (WHERE logger='keystonemiddleware.auth_token') AS ks_all,
       count(*) FILTER (WHERE level='CRITICAL') AS crit_all,
       count(*) FILTER (WHERE level='CRITICAL' AND logger<>'keystonemiddleware.auth_token') AS crit_other,
       count(*) FILTER (WHERE level='WARNING' AND logger='nova.virt.libvirt.imagecache' AND left(message, 17) = 'Unknown base file') AS ubf,
       count(*) FILTER (WHERE level='WARNING' AND logger='nova.virt.libvirt.imagecache' AND left(message, 17) <> 'Unknown base file') AS ic_other
FROM o;
-- incidents at 5-minute gap per problem (partition by logger+level-defined problem, global time order)
WITH o AS (SELECT origin_file AS f, "timestamp"::timestamp AS t, logger, level, message FROM read_parquet('/data/loghub/openstack.parquet')),
p AS (
  SELECT CASE WHEN logger='oslo_service.periodic_task' AND level='ERROR' THEN 'imagecache_traceback'
              WHEN logger='keystonemiddleware.auth_token' THEN 'auth_token'
              WHEN logger='nova.virt.libvirt.imagecache' AND level='WARNING' AND left(message,17)='Unknown base file' THEN 'unknown_base_file' END AS prob, t, f
  FROM o
), g AS (SELECT prob, t, f, lag(t) OVER (PARTITION BY prob ORDER BY t) AS pv FROM p WHERE prob IS NOT NULL)
SELECT prob, count(*) AS lines, count(*) FILTER (WHERE pv IS NULL OR t - pv > INTERVAL '5 minutes') AS incidents,
       count(DISTINCT f) AS files, max(epoch(t)-epoch(pv)) AS max_gap_s FROM g GROUP BY prob ORDER BY prob;
-- owner_map logger rows
SELECT * FROM owner_map WHERE key_value IN ('oslo_service.periodic_task','nova.virt.libvirt.imagecache','keystonemiddleware.auth_token') OR lower(dataset)='openstack' ORDER BY key_type, key_value;
SELECT logger, team, count(*) FROM os_ev WHERE logger IN ('oslo_service.periodic_task','nova.virt.libvirt.imagecache','keystonemiddleware.auth_token') AND level <> 'INFO' GROUP BY 1,2;


-- ==== 11 labelled instances at positions 1-4 of 2,069; position 5 unlabelled (26.69); 100 lines, all INFO; latency 0.234015 vs 0.234055
\echo '=== c11'
WITH o AS (SELECT * FROM read_parquet('/data/loghub/openstack.parquet')),
lab AS (SELECT * FROM (VALUES ('544fd51c-4edc-4780-baae-ba1d80a0acfc'),('ae651dff-c7ad-43d6-ac96-bbcd820ccca8'),('a445709b-6ad0-40ec-8860-bec60b6ca0c2'),('1643649d-2f42-4303-bfcd-7798baec19f9')) v(iid)),
sp AS (
  SELECT instance_id, max(CAST(nullif(regexp_extract(message, 'Took ([0-9]+\.[0-9]+) seconds to spawn the instance on the hypervisor', 1), '') AS DOUBLE)) AS spawn_s
  FROM o WHERE instance_id IS NOT NULL AND instance_id <> '' GROUP BY instance_id
), r AS (
  SELECT instance_id, spawn_s, row_number() OVER (ORDER BY spawn_s DESC NULLS LAST, instance_id) AS pos,
         instance_id IN (SELECT iid FROM lab) AS labelled
  FROM sp
)
SELECT (SELECT count(*) FROM sp) AS n_instances, (SELECT count(spawn_s) FROM sp) AS n_spawned, pos, instance_id, spawn_s, labelled FROM r WHERE pos <= 6 ORDER BY pos;
WITH o AS (SELECT * FROM read_parquet('/data/loghub/openstack.parquet'))
SELECT count(*) AS lines, count(*) FILTER (WHERE level='INFO') AS info, count(DISTINCT instance_id) AS inst, min(origin_file), max(origin_file)
FROM o WHERE instance_id IN ('544fd51c-4edc-4780-baae-ba1d80a0acfc','ae651dff-c7ad-43d6-ac96-bbcd820ccca8','a445709b-6ad0-40ec-8860-bec60b6ca0c2','1643649d-2f42-4303-bfcd-7798baec19f9');
-- note only: substring presence of the UUIDs in the message (strpos), not used for counts
WITH o AS (SELECT * FROM read_parquet('/data/loghub/openstack.parquet'))
SELECT count(*) AS lines_mentioning, count(*) FILTER (WHERE level='INFO') AS info FROM o
WHERE strpos(message,'544fd51c-4edc-4780-baae-ba1d80a0acfc')>0 OR strpos(message,'ae651dff-c7ad-43d6-ac96-bbcd820ccca8')>0 OR strpos(message,'a445709b-6ad0-40ec-8860-bec60b6ca0c2')>0 OR strpos(message,'1643649d-2f42-4303-bfcd-7798baec19f9')>0;
SELECT is_abnormal_file, count(latency_s) AS calls, avg(latency_s) AS mean_lat, round(avg(latency_s), 4) AS mean4 FROM read_parquet('/data/loghub/openstack.parquet') GROUP BY 1 ORDER BY 1;
SELECT origin_file, count(latency_s) AS calls, avg(latency_s) FROM read_parquet('/data/loghub/openstack.parquet') GROUP BY 1 ORDER BY 1;


-- ==== 12 29,670 signatures; 4 mixed; 9 lines disagree (99.9998%); TP 348,454 FP 3 FN 6; level detector 348,460 / 508,755 / 0
\echo '=== c12'
WITH a AS (
  SELECT label, level,
         regexp_replace(regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'), '[0-9]+', '{n}', 'g') AS sig
  FROM read_parquet('/data/loghub/bgl.parquet')
), sl AS (SELECT sig, label, count(*) AS n FROM a GROUP BY sig, label),
ps AS (
  SELECT sig, sum(n) AS tot, max(n) AS mx, count(*) AS nlabels,
         max(n) FILTER (WHERE label = '-') AS n_dash,
         max(n) FILTER (WHERE label <> '-') AS n_best_alert
  FROM sl GROUP BY sig
), pred AS (
  -- predict alert iff the best non-'-' label strictly beats '-' (ties go to '-')
  SELECT sig, coalesce(n_best_alert, 0) > coalesce(n_dash, 0) AS pred_alert FROM ps
)
SELECT (SELECT count(*) FROM ps) AS n_sigs, (SELECT sum(tot) FROM ps) AS lines,
       (SELECT count(*) FROM ps WHERE nlabels > 1) AS multi_label_sigs,
       (SELECT sum(tot - mx) FROM ps) AS disagree_lines,
       (SELECT round((1 - sum(tot - mx)::DOUBLE / sum(tot)) * 100, 4) FROM ps) AS agree_pct,
       sum(CASE WHEN p.pred_alert AND a.label <> '-' THEN 1 ELSE 0 END) AS tp,
       sum(CASE WHEN p.pred_alert AND a.label = '-' THEN 1 ELSE 0 END) AS fp,
       sum(CASE WHEN NOT p.pred_alert AND a.label <> '-' THEN 1 ELSE 0 END) AS fn,
       sum(CASE WHEN a.level IN ('FATAL','FAILURE') AND a.label <> '-' THEN 1 ELSE 0 END) AS lv_tp,
       sum(CASE WHEN a.level IN ('FATAL','FAILURE') AND a.label = '-' THEN 1 ELSE 0 END) AS lv_fp,
       sum(CASE WHEN a.level NOT IN ('FATAL','FAILURE') AND a.label <> '-' THEN 1 ELSE 0 END) AS lv_fn
FROM a JOIN pred p USING (sig);
WITH a AS (
  SELECT label, regexp_replace(regexp_replace(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'), '[0-9]+', '{n}', 'g') AS sig
  FROM read_parquet('/data/loghub/bgl.parquet')
), sl AS (SELECT sig, label, count(*) AS n FROM a GROUP BY sig, label),
m AS (SELECT sig FROM sl GROUP BY sig HAVING count(*) > 1)
SELECT left(sl.sig, 70) AS sig, label, n FROM sl JOIN m USING (sig) ORDER BY sl.sig, n DESC;
SELECT round(348460::DOUBLE/(348460+508755), 6) AS precision;


-- ==== 13 lead_bgl_daily sum 4,747,963; mgr_bgl_risk sum 348,460
\echo '=== c13'
SELECT sum(lines) AS lead_total FROM lead_bgl_daily;
SELECT sum(alert_lines) AS mgr_total, count(*) AS mgr_rows FROM mgr_bgl_risk;
-- claim 14: @@ on the index relation
SELECT count(*) AS dash_assert_phrase FROM bgl_idx WHERE content @@ ts_phrase('idoproxydb hit ASSERT condition') AND alert_category = '-';
SELECT alert_category = '-' AS dash, count(*) FROM bgl_idx WHERE content @@ ts_phrase('idoproxydb hit ASSERT condition') GROUP BY 1;
-- claim 14 cross-check: prefix equality on raw content
SELECT count(*) AS dash_prefix_eq FROM read_parquet('/data/loghub/bgl.parquet') WHERE label = '-' AND left(content, 31) = 'idoproxydb hit ASSERT condition';
-- note only (not evidence): LIKE
SELECT count(*) AS dash_like_note FROM bgl_ev WHERE alert_category = '-' AND content LIKE '%idoproxydb hit ASSERT condition%';
-- claim 16, written differently: per-component sums on the index relation
SELECT sum(n) AS dtlb_phrase FROM (SELECT component, count(id) AS n FROM bgl_idx WHERE content @@ ts_phrase('data TLB error interrupt') GROUP BY component) x;
SELECT sum(n) AS ciod_term FROM (SELECT level, count(id) AS n FROM bgl_idx WHERE content @@ 'ciod' GROUP BY level) x;
SELECT count(*) AS dtlb_lucene FROM bgl_idx WHERE content @@ to_tsquery('"data TLB error interrupt"');


-- ==== 14-15 84,253 '-' ASSERT lines (@@ ts_phrase on bgl_idx); 42 labels; 6 levels; owner_map 23 rows; 0 UNOWNED
\echo '=== c15'
SELECT count(DISTINCT label) AS labels, count(DISTINCT level) AS levels, count(*) FILTER (WHERE label IS NULL) AS null_labels, count(*) FILTER (WHERE level IS NULL) AS null_levels FROM read_parquet('/data/loghub/bgl.parquet');
SELECT count(*) AS owner_rows FROM owner_map;
SELECT dataset, key_type, count(*) FROM owner_map GROUP BY 1,2 ORDER BY 1,2;
SELECT 'bgl' AS ds, count(*) AS lines, count(*) FILTER (WHERE team = 'UNOWNED' OR team IS NULL OR team = '') AS unowned FROM bgl_ev
UNION ALL SELECT 'os', count(*), count(*) FILTER (WHERE team = 'UNOWNED' OR team IS NULL OR team = '') FROM os_ev;
-- independent team derivation from owner_map on the raw Parquet (BGL: component; OS: logger > service)
WITH b AS (SELECT component FROM read_parquet('/data/loghub/bgl.parquet')),
m AS (SELECT key_value, team FROM owner_map WHERE lower(dataset)='bgl' AND key_type='component')
SELECT 'bgl' AS ds, count(*) AS lines, count(m.team) AS mapped, count(*) FILTER (WHERE m.team = 'compute-platform') AS compute_platform FROM b LEFT JOIN m ON m.key_value = b.component;
WITH o AS (SELECT logger, service FROM read_parquet('/data/loghub/openstack.parquet')),
ml AS (SELECT key_value, team FROM owner_map WHERE lower(dataset)='openstack' AND key_type='logger'),
ms AS (SELECT key_value, team FROM owner_map WHERE lower(dataset)='openstack' AND key_type='service')
SELECT 'os' AS ds, count(*) AS lines, count(coalesce(ml.team, ms.team)) AS mapped FROM o LEFT JOIN ml ON ml.key_value = o.logger LEFT JOIN ms ON ms.key_value = o.service;
-- os_ev sanity vs raw for claim 10
SELECT count(*) FILTER (WHERE level IN ('ERROR','CRITICAL')) AS err_crit, count(*) FILTER (WHERE level='CRITICAL') AS crit,
       count(*) FILTER (WHERE logger='nova.virt.libvirt.imagecache' AND level='WARNING' AND left(content,17)='Unknown base file') AS ubf,
       count(DISTINCT (source_file, pid, ts, logger, level)) FILTER (WHERE logger='oslo_service.periodic_task' AND level='ERROR') AS pt_records
FROM os_ev;


-- ==== 17 remote footer: 1,000,000,000 rows, 1,624 row groups, 40,991,166,725 bytes
\echo '=== c17a'
SET enable_external_file_cache = false;
\x on
SELECT * FROM parquet_file_metadata('https://public-pme.s3.eu-west-3.amazonaws.com/text_bench/part_000.parquet');
SELECT * FROM parquet_metadata('https://public-pme.s3.eu-west-3.amazonaws.com/text_bench/part_000.parquet') WHERE path_in_schema = 'TimestampTime' AND row_group_id = 0;


-- ==== 17 remote footer: 10 s slice 10 row groups / 6,144,000 rows; 1 s slice 2 / 1,228,800; ServiceName 297,560,211 B; Body 9,074,835,467 B
\echo '=== c17b'
SET enable_external_file_cache = false;
WITH m AS (SELECT * FROM parquet_metadata('https://public-pme.s3.eu-west-3.amazonaws.com/text_bench/part_000.parquet')),
tt AS (SELECT row_group_id, row_group_num_rows AS n, CAST(stats_min_value AS TIMESTAMPTZ) AS lo, CAST(stats_max_value AS TIMESTAMPTZ) AS hi FROM m WHERE path_in_schema = 'TimestampTime')
SELECT count(*) AS rgs, sum(n) AS rows_total, min(lo) AS tmin, max(hi) AS tmax,
       count(*) FILTER (WHERE lo < TIMESTAMPTZ '2025-09-23 00:05:10+00' AND hi >= TIMESTAMPTZ '2025-09-23 00:05:00+00') AS rg_10s,
       sum(n) FILTER (WHERE lo < TIMESTAMPTZ '2025-09-23 00:05:10+00' AND hi >= TIMESTAMPTZ '2025-09-23 00:05:00+00') AS rows_10s,
       count(*) FILTER (WHERE lo < TIMESTAMPTZ '2025-09-23 00:05:01+00' AND hi >= TIMESTAMPTZ '2025-09-23 00:05:00+00') AS rg_1s,
       sum(n) FILTER (WHERE lo < TIMESTAMPTZ '2025-09-23 00:05:01+00' AND hi >= TIMESTAMPTZ '2025-09-23 00:05:00+00') AS rows_1s
FROM tt;
WITH m AS (SELECT * FROM parquet_metadata('https://public-pme.s3.eu-west-3.amazonaws.com/text_bench/part_000.parquet'))
SELECT path_in_schema, sum(total_compressed_size) AS compressed_bytes, count(*) AS chunks FROM m WHERE path_in_schema IN ('ServiceName','Body') GROUP BY 1 ORDER BY 1;


-- ==== 16 full-text on the index relation: phrase 152,734; term 'ciod' 350,567
\echo '=== c16'
SELECT (SELECT count(*) FROM bgl_idx WHERE content @@ ts_phrase('data TLB error interrupt')) AS phrase_dtlb,
       (SELECT count(*) FROM bgl_idx WHERE content @@ 'ciod')                              AS term_ciod;
