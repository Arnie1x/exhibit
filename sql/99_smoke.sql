-- sql/99_smoke.sql
-- The headline numbers. If these print, the build is alive and the demo's claims are real.
-- Every figure here is quoted in PLAN.md and README.md; re-run this after any reload.

\pset border 2
\echo '=== 1. corpus loaded ==='
SELECT 'BGL' AS dataset, count(*) AS rows FROM bgl_ev
UNION ALL SELECT 'OpenStack', count(*) FROM os_ev;

\echo '=== 2. alert lines vs episodes (the whole thesis in two numbers) ==='
SELECT (SELECT count(*) FROM bgl_ev WHERE is_alert)                    AS alert_lines,
       (SELECT count(*) FROM (SELECT DISTINCT signature, midplane, episode_no
                              FROM bgl_episode) e)                      AS episodes_failure_domain,
       (SELECT count(*) FROM (
          WITH m AS (SELECT signature, ts,
                       CASE WHEN LAG(ts) OVER (PARTITION BY signature ORDER BY ts) IS NULL
                              OR ts - LAG(ts) OVER (PARTITION BY signature ORDER BY ts)
                                 > INTERVAL '5 minutes'
                            THEN 1 ELSE 0 END AS is_new
                     FROM bgl_sig WHERE is_alert)
          SELECT DISTINCT signature,
                 SUM(is_new) OVER (PARTITION BY signature ORDER BY ts
                                   ROWS UNBOUNDED PRECEDING) AS ep
          FROM m) z)                                                AS episodes_global;

\echo '=== 3. ranking inversion: top 6 by LINES vs top 6 by EPISODES ==='
SELECT left(signature, 52) AS signature, lines, peak_nodes, episodes
FROM bgl_signature_incidents ORDER BY lines DESC LIMIT 6;
SELECT left(signature, 52) AS signature, episodes, lines, peak_nodes
FROM bgl_signature_incidents ORDER BY episodes DESC LIMIT 6;

\echo '=== 4. the one-node burst that makes line counts lie (every node with alerts that day) ==='
-- The whole calendar day, not a guessed window: the burst runs to 23:39, and a window that
-- stopped at 23:00 used to report 136,209 of its 152,183 lines.
SELECT node, min(ts) AS from_ts, max(ts) AS to_ts, max(ts) - min(ts) AS span, count(*) AS lines,
       round(100.0 * count(*) / (SELECT count(*) FROM bgl_ev WHERE is_alert), 2) AS pct_of_alert_lines
FROM bgl_ev
WHERE is_alert AND ts >= TIMESTAMP '2005-06-11' AND ts < TIMESTAMP '2005-06-12'
GROUP BY node ORDER BY lines DESC;

\echo '=== 4b. THE MONEY COMPARISON: one node vs the whole fleet (both rows computed) ==='
SELECT 'single-node burst, 2005-06-11' AS event, count(*) AS lines, count(DISTINCT node) AS nodes
FROM bgl_ev WHERE is_alert AND ts >= TIMESTAMP '2005-06-11' AND ts < TIMESTAMP '2005-06-12'
UNION ALL
SELECT 'fleet event, 2005-06-14', count(*), count(DISTINCT node)
FROM bgl_ev WHERE is_alert AND ts >= TIMESTAMP '2005-06-14' AND ts < TIMESTAMP '2005-06-15';

\echo '=== 5. the fleet-wide event that looked small ==='
SELECT ts::date AS day, count(*) AS lines, count(DISTINCT node) AS nodes
FROM bgl_ev WHERE is_alert AND ts >= TIMESTAMP '2005-06-13' AND ts < TIMESTAMP '2005-06-15'
GROUP BY 1 ORDER BY 1;

\echo '=== 6. OpenStack: the whole error surface is one bug ==='
SELECT level, count(*) AS lines FROM os_ev GROUP BY level ORDER BY 2 DESC;

\echo '=== 7. labelled anomalies are duration outliers, not level outliers ==='
-- The four injected-anomaly VMs must appear at the top. They do: positions 1-4.
SELECT instance_id, lines, spawn_s, build_s, EXTRACT(EPOCH FROM lifetime) AS lifetime_s
FROM os_instance_durations ORDER BY coalesce(spawn_s, build_s) DESC NULLS LAST LIMIT 6;

\echo '=== 7b. the four labelled anomalies from anomaly_labels.txt ==='
SELECT instance_id, spawn_s, build_s,
       (instance_id IN ('544fd51c-4edc-4780-baae-ba1d80a0acfc',
                        'ae651dff-c7ad-43d6-ac96-bbcd820ccca8',
                        'a445709b-6ad0-40ec-8860-bec60b6ca0c2',
                        '1643649d-2f42-4303-bfcd-7798baec19f9')) AS is_labelled_anomaly
FROM os_instance_durations ORDER BY coalesce(spawn_s, build_s) DESC NULLS LAST LIMIT 6;

\echo '=== 8. ownership coverage ==='
SELECT team, count(*) AS bgl_lines FROM bgl_ev GROUP BY team ORDER BY 2 DESC;
