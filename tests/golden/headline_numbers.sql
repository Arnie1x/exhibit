-- tests/golden/headline_numbers.sql
-- Independent recomputation of the BGL headline numbers (sql-verifier, 17 Oct 2026).
-- Written fresh: it does not use bgl_sig, bgl_episode, bgl_incident, bgl_signature_incidents,
-- sql/30_views.sql or sql/99_smoke.sql. Read-only: SELECTs only, no DDL, no writes.
-- Each claim is computed twice where possible: from the raw Parquet (checks the derive step)
-- and from bgl_ev.
--
-- Run (Windows host, no host psql):
--   export MSYS_NO_PATHCONV=1
--   docker exec -i serenedb psql -h 127.0.0.1 -p 7890 -U postgres -P pager=off -f - < tests/golden/headline_numbers.sql
--
-- Operators: plain equality/inequality on label, regexp_replace masking, LAG / ROWS-frame windows.
-- No full-text (@@) and no LIKE count is used anywhere in this file.

\set ON_ERROR_STOP on
SET statement_timeout = '120s';  -- accepted but NOT enforced by serened 26.09.1.3 (it warns)

-- ---------------------------------------------------------------------------------------------
-- C1. BGL alert lines = lines whose label is not '-'.            expected 348460 (both sources)
-- ---------------------------------------------------------------------------------------------
SELECT 'C1 alert lines (raw parquet, label <> ''-'')' AS claim, 348460 AS stated,
       count(*) AS independent, count(*) = 348460 AS match
FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'
UNION ALL
SELECT 'C1 alert lines (bgl_ev, alert_category <> ''-'')', 348460, count(*), count(*) = 348460
FROM bgl_ev WHERE alert_category <> '-';

-- ---------------------------------------------------------------------------------------------
-- C2 / C2b. Episodes at a 5-minute gap.
--   signature = content, UUIDs -> '{uuid}' first, then digit runs -> '{n}'
--   midplane  = first two '-'-parts of node when node has >= 2 '-', else 'UNKNOWN'
--   start     = first line of its group in ts order, or gap to previous line of the group > 5 min
-- Formulation A (raw parquet): count start rows directly with LAG and an INTERVAL comparison.
-- Formulation B (bgl_ev):      groups + count of gaps > 300 s, on numeric epoch, ROWS frame.
-- Tie sensitivity: none. No two alert lines share a ts (microsecond timestamps), and the count of
-- gaps > 5 min is invariant to the order of tied rows anyway. No gap lies within 1 ms of 300 s,
-- so '>' and '>=' give the same counts.
--   expected: C2 19250 (signature x midplane), C2b 1377 (signature), 100 signatures,
--             2657 signature x midplane groups, 129 midplanes (incl. 'UNKNOWN')
-- ---------------------------------------------------------------------------------------------
WITH a AS (
  SELECT "timestamp"::timestamp AS t,
         regexp_replace(
           regexp_replace(content,
             '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '{uuid}', 'g'),
           '[0-9]+', '{n}', 'g') AS sig,
         CASE WHEN length(node) - length(replace(node, '-', '')) >= 2
              THEN split_part(node, '-', 1) || '-' || split_part(node, '-', 2)
              ELSE 'UNKNOWN' END AS mp
  FROM read_parquet('/data/loghub/bgl.parquet') WHERE label <> '-'
), g AS (
  SELECT t,
         LAG(t) OVER (PARTITION BY sig, mp ORDER BY t) AS prev_sm,
         LAG(t) OVER (PARTITION BY sig ORDER BY t)     AS prev_s
  FROM a
)
SELECT 'C2 episodes, 5 min, signature x midplane (raw, LAG start rows)' AS claim, 19250 AS stated,
       count(*) FILTER (WHERE prev_sm IS NULL OR t - prev_sm > INTERVAL '5 minutes') AS independent,
       count(*) FILTER (WHERE prev_sm IS NULL OR t - prev_sm > INTERVAL '5 minutes') = 19250 AS match
FROM g
UNION ALL
SELECT 'C2b episodes, 5 min, signature only (raw, LAG start rows)', 1377,
       count(*) FILTER (WHERE prev_s IS NULL OR t - prev_s > INTERVAL '5 minutes'),
       count(*) FILTER (WHERE prev_s IS NULL OR t - prev_s > INTERVAL '5 minutes') = 1377
FROM g;

WITH a AS (
  SELECT extract(epoch FROM ts) AS e,
         regexp_replace(
           regexp_replace(content, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '{uuid}', 'g'),
           '\d+', '{n}', 'g') AS sig,
         CASE WHEN node LIKE '%-%-%' THEN regexp_extract(node, '^([^-]*-[^-]*)-', 1)
              ELSE 'UNKNOWN' END AS mp
  FROM bgl_ev WHERE is_alert
), d AS (
  SELECT e - max(e) OVER (PARTITION BY sig, mp ORDER BY e ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING) AS gap_sm,
         e - max(e) OVER (PARTITION BY sig     ORDER BY e ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING) AS gap_s
  FROM a
), k AS (
  SELECT (SELECT count(*) FROM (SELECT DISTINCT sig, mp FROM a) x)        AS groups_sm,
         (SELECT count(DISTINCT sig) FROM a)                              AS groups_s,
         (SELECT count(*) FILTER (WHERE gap_sm > 300) FROM d)             AS gaps_sm,
         (SELECT count(*) FILTER (WHERE gap_s  > 300) FROM d)             AS gaps_s
)
SELECT 'C2 episodes, 5 min, signature x midplane (bgl_ev, groups + gaps > 300 s)' AS claim, 19250 AS stated,
       groups_sm + gaps_sm AS independent, groups_sm + gaps_sm = 19250 AS match FROM k
UNION ALL
SELECT 'C2b episodes, 5 min, signature only (bgl_ev, groups + gaps > 300 s)', 1377,
       groups_s + gaps_s, groups_s + gaps_s = 1377 FROM k;

-- Tie and boundary checks for C2: expected 0, 0, 0
SELECT 'C2 check: alert ts values shared by > 1 alert line' AS check_, count(*) AS value
FROM (SELECT ts FROM bgl_ev WHERE is_alert GROUP BY ts HAVING count(*) > 1) x
UNION ALL
SELECT 'C2 check: alert lines whose midplane differs from bgl_ev.midplane', count(*)
FROM bgl_ev
WHERE is_alert
  AND midplane <> CASE WHEN length(node) - length(replace(node, '-', '')) >= 2
                       THEN split_part(node, '-', 1) || '-' || split_part(node, '-', 2)
                       ELSE 'UNKNOWN' END
UNION ALL
SELECT 'C2 check: alert lines carrying a UUID', count(*)
FROM bgl_ev WHERE is_alert
  AND regexp_matches(content, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');

-- ---------------------------------------------------------------------------------------------
-- C3. The one-node burst on 2005-06-11 (ts calendar day, US Pacific wall clock).
--   Per node, alert lines that day. expected: one node only, R30-M0-N9-C:J16-U01,
--   152183 alert lines, 17:17:44.605961 -> 23:39:32.87774, span 06:21:48.271779 (22908.27 s),
--   43.67 % of 348460. (152182 KERNDTLB + 1 KERNMC.)
-- ---------------------------------------------------------------------------------------------
SELECT 'C3 per node, 2005-06-11 (raw parquet)' AS claim, node,
       count(*) AS alert_lines,
       min("timestamp"::timestamp) AS first_alert, max("timestamp"::timestamp) AS last_alert,
       max("timestamp"::timestamp) - min("timestamp"::timestamp) AS span,
       round(100.0 * count(*) / 348460, 2) AS pct_of_alerts
FROM read_parquet('/data/loghub/bgl.parquet')
WHERE label <> '-' AND CAST("timestamp"::timestamp AS DATE) = DATE '2005-06-11'
GROUP BY node ORDER BY alert_lines DESC LIMIT 5;

SELECT 'C3 per node, 2005-06-11 (bgl_ev)' AS claim, node, count(*) AS alert_lines,
       min(ts) AS first_alert, max(ts) AS last_alert, max(ts) - min(ts) AS span,
       round(100.0 * count(*) / 348460, 2) AS pct_of_alerts
FROM bgl_ev
WHERE is_alert AND ts >= TIMESTAMP '2005-06-11' AND ts < TIMESTAMP '2005-06-12'
GROUP BY node ORDER BY alert_lines DESC LIMIT 5;

-- The stated 136,209 reproduces only as the window 17:00 <= ts < 23:00, i.e. the burst with its
-- last hour cut off. expected: 136209 in that window, 15974 after 23:00, 0 other nodes in window.
SELECT 'C3 stated 136209 (window ts < 23:00:00, same node)' AS claim, 136209 AS stated,
       count(*) FILTER (WHERE ts < TIMESTAMP '2005-06-11 23:00:00') AS independent,
       count(*) FILTER (WHERE ts < TIMESTAMP '2005-06-11 23:00:00') = 136209 AS match
FROM bgl_ev WHERE is_alert AND node = 'R30-M0-N9-C:J16-U01'
  AND ts >= TIMESTAMP '2005-06-11' AND ts < TIMESTAMP '2005-06-12'
UNION ALL
SELECT 'C3 burst alert lines after 23:00:00 (omitted by the stated window)', NULL,
       count(*), NULL
FROM bgl_ev WHERE is_alert AND node = 'R30-M0-N9-C:J16-U01'
  AND ts >= TIMESTAMP '2005-06-11 23:00:00' AND ts < TIMESTAMP '2005-06-12'
UNION ALL
SELECT 'C3 alert lines on other nodes, 17:17:44 -> 23:39:33', NULL, count(*), NULL
FROM bgl_ev WHERE is_alert AND node <> 'R30-M0-N9-C:J16-U01'
  AND ts >= TIMESTAMP '2005-06-11 17:17:44' AND ts <= TIMESTAMP '2005-06-11 23:39:33';

-- ---------------------------------------------------------------------------------------------
-- C4. Fleet days (ts calendar day). expected 2005-06-13: 17409 lines / 16644 nodes;
--                                    2005-06-14: 49154 lines / 22529 nodes.
-- ---------------------------------------------------------------------------------------------
WITH s(d, lines, nodes) AS (VALUES (DATE '2005-06-13', 17409, 16644), (DATE '2005-06-14', 49154, 22529)),
r AS (
  SELECT CAST("timestamp"::timestamp AS DATE) AS d, count(*) AS lines, count(DISTINCT node) AS nodes
  FROM read_parquet('/data/loghub/bgl.parquet')
  WHERE label <> '-' AND CAST("timestamp"::timestamp AS DATE) IN (DATE '2005-06-13', DATE '2005-06-14')
  GROUP BY 1
), e AS (
  SELECT ts::DATE AS d, count(*) AS lines, count(DISTINCT node) AS nodes
  FROM bgl_ev WHERE is_alert AND ts >= TIMESTAMP '2005-06-13' AND ts < TIMESTAMP '2005-06-15'
  GROUP BY 1
)
SELECT 'C4 ' || s.d::VARCHAR AS claim, s.lines AS stated_lines, r.lines AS raw_lines, e.lines AS ev_lines,
       s.nodes AS stated_nodes, r.nodes AS raw_nodes, e.nodes AS ev_nodes,
       (s.lines = r.lines AND s.lines = e.lines AND s.nodes = r.nodes AND s.nodes = e.nodes) AS match
FROM s JOIN r USING (d) JOIN e USING (d) ORDER BY s.d;
