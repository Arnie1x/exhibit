-- sql/90_queries.sql  (make demo)
-- The two worked investigations of the team plan §9, role by role, exactly as the video runs
-- them. Every number printed here is computed by the statement above it; none is typed in.
--
-- Each step names the MCP tool it stands for, so the tool's output can be checked against it,
-- and runs under that role (SET ROLE): the engineer, lead and manager answers read different
-- relations, and the database refuses anything outside a role's views (sql/50_roles.sql).
-- Episodes always state their gap; text counts always state their operator.
--
-- The last section reads the ground-truth labels. It is validation, not an agent path: no tool
-- and no role view can reach it (Stage 5 moves it into the ground-truth script).
--
-- Run after make bootstrap:
--   psql -h 127.0.0.1 -p 7890 -U postgres -f sql/90_queries.sql

\set ON_ERROR_STOP on
\set QUIET on
\pset border 2
\pset footer off

\echo ''
\echo '################################################################################'
\echo '# W1 (BGL): "Which problem should we fix first?"'
\echo '################################################################################'

SET ROLE exhibit_engineer;
\echo ''
\echo '=== scope (describe_data) ==='
SELECT 'BGL' AS dataset, count(*) AS lines, count(*) FILTER (WHERE is_alert) AS alert_lines,
       min(ts) AS first_ts, max(ts) AS last_ts
FROM bgl_ev;

\echo ''
\echo '--- W1 engineer -----------------------------------------------------------------'
\echo '=== E1 top_signatures(rank_by = lines): the loudest alert signatures ==='
SELECT left(signature, 64) AS signature, alert_category, alert_lines, episodes_5min, nodes_affected, top_node_pct
FROM bgl_signature_stats
ORDER BY alert_lines DESC, signature_id
LIMIT 5;

\echo '=== E2 search_logs(phrase "data TLB error interrupt"), operator @@ ts_phrase on bgl_idx ==='
SELECT count(*) AS total_matches
FROM bgl_idx
WHERE content @@ ts_phrase('data TLB error interrupt');
\echo '    ... the same matches by node (count_events with the query):'
SELECT node, count(*) AS lines, min(ts) AS first_ts, max(ts) AS last_ts, max(ts) - min(ts) AS span
FROM bgl_idx
WHERE content @@ ts_phrase('data TLB error interrupt')
GROUP BY node
ORDER BY lines DESC, node
LIMIT 3;

\echo '=== E3 count_events(group_by = node, one day each): one node vs the fleet, alert lines ==='
\echo '    every alert line of each calendar day; nodes = how many nodes logged them'
SELECT 'single-node burst, 2005-06-11' AS event, count(*) AS alert_lines, count(DISTINCT node) AS nodes,
       min(ts) AS first_ts, max(ts) AS last_ts
FROM bgl_ev
WHERE is_alert AND ts >= TIMESTAMP '2005-06-11' AND ts < TIMESTAMP '2005-06-12'
UNION ALL
SELECT 'fleet event, 2005-06-14', count(*), count(DISTINCT node), min(ts), max(ts)
FROM bgl_ev
WHERE is_alert AND ts >= TIMESTAMP '2005-06-14' AND ts < TIMESTAMP '2005-06-15';

\echo '=== E4 episodes(signature = DTLB): lines vs incidents at gaps of 1, 5 and 60 minutes ==='
SELECT signature, alert_lines,
       episodes_1min, episodes_5min, episodes_60min,
       episodes_1min_global, episodes_5min_global, episodes_60min_global
FROM bgl_episode_sensitivity
WHERE signature = 'data TLB error interrupt';
\echo '    (episodes_*: per signature x midplane; *_global: per signature only)'
RESET ROLE;

\echo ''
\echo '--- W1 team lead (no raw lines, no search) ---------------------------------------'
SET ROLE exhibit_lead;
\echo '=== L1 ownership(dataset = BGL): share of lines and of alert lines per owning team ==='
SELECT team, matched_on, lines, pct_lines, problem_lines AS alert_lines, pct_problem_lines AS pct_alert_lines
FROM ownership_coverage
WHERE dataset = 'BGL'
ORDER BY lines DESC;

\echo '=== L2 top_signatures(rank_by = episodes, gap 5 min, signature x midplane) ==='
SELECT left(signature, 64) AS signature, team, episodes_5min, alert_lines, nodes_affected, peak_nodes_per_episode, active_days
FROM bgl_signature_stats
ORDER BY episodes_5min DESC, signature_id
LIMIT 6;

\echo '=== L3 count_events(group_by = team): lines vs incidents (gap 5 min) ==='
SELECT team, count(*) AS signatures, sum(alert_lines) AS alert_lines,
       round(100 * sum(alert_lines)::DOUBLE / sum(sum(alert_lines)) OVER (), 2) AS pct_alert_lines,
       sum(episodes_5min) AS episodes_5min,
       round(100 * sum(episodes_5min)::DOUBLE / sum(sum(episodes_5min)) OVER (), 2) AS pct_episodes
FROM bgl_signature_stats
GROUP BY team
ORDER BY episodes_5min DESC;

\echo '=== L4 trend(bucket = week): incidents per week (gap 5 min) for the top 4 by episodes ==='
\echo '    slope = regr_slope(incidents, week number) over every week, zero weeks included;'
\echo '    last_9_weeks anchors on the dataset last week, not on today'
WITH top AS (
    SELECT signature_id, signature FROM bgl_signature_stats
    ORDER BY episodes_5min DESC, signature_id LIMIT 4
), weeks AS (
    SELECT w, row_number() OVER (ORDER BY w) - 1 AS wk
    FROM generate_series((SELECT date_trunc('week', min(started)) FROM bgl_incident),
                         (SELECT date_trunc('week', max(started)) FROM bgl_incident),
                         INTERVAL '7 days') g(w)
), per_week AS (
    SELECT t.signature_id, t.signature, k.w, k.wk, count(i.signature_id) AS incidents
    FROM top t
    CROSS JOIN weeks k
    LEFT JOIN bgl_incident i
           ON i.signature_id = t.signature_id AND date_trunc('week', i.started) = k.w
    GROUP BY t.signature_id, t.signature, k.w, k.wk
)
SELECT left(signature, 64) AS signature, count(*) AS weeks, count(*) FILTER (WHERE incidents > 0) AS active_weeks,
       sum(incidents) AS incidents, max(incidents) AS peak_week_incidents,
       round(regr_slope(incidents, wk), 3) AS slope_per_week,
       sum(incidents) FILTER (WHERE w >= (SELECT max(w) FROM weeks) - INTERVAL '8 weeks') AS last_9_weeks
FROM per_week
GROUP BY signature_id, signature
ORDER BY incidents DESC, signature_id;

\echo '=== L4b the weekly bars behind the slide 10 chart: top 2 by episodes, active weeks only ==='
\echo '    week_no counts from the first week of the corpus (0 = 2005-05-30); 32 weeks in all'
WITH top AS (
    SELECT signature_id, signature FROM bgl_signature_stats
    ORDER BY episodes_5min DESC, signature_id LIMIT 2
), weeks AS (
    SELECT w, row_number() OVER (ORDER BY w) - 1 AS wk
    FROM generate_series((SELECT date_trunc('week', min(started)) FROM bgl_incident),
                         (SELECT date_trunc('week', max(started)) FROM bgl_incident),
                         INTERVAL '7 days') g(w)
), per_week AS (
    SELECT t.signature_id, t.signature, k.w, k.wk, count(i.signature_id) AS incidents
    FROM top t
    CROSS JOIN weeks k
    LEFT JOIN bgl_incident i
           ON i.signature_id = t.signature_id AND date_trunc('week', i.started) = k.w
    GROUP BY t.signature_id, t.signature, k.w, k.wk
)
SELECT left(signature, 40) AS signature, wk AS week_no, w::date AS week_of, incidents
FROM per_week
WHERE incidents > 0
ORDER BY signature_id, wk;
RESET ROLE;

\echo ''
\echo '--- W1 manager (no log text, no node IDs) ----------------------------------------'
SET ROLE exhibit_manager;
\echo '=== M1 episodes: alert lines -> incidents (gap 5 min, signature x midplane) ==='
SELECT sum(alert_lines) AS alert_lines, sum(episodes_5min) AS incidents_5min,
       round(sum(alert_lines)::DOUBLE / sum(episodes_5min), 1) AS lines_per_incident
FROM mgr_bgl_risk;

\echo '=== M2 top_signatures(rank_by = blast radius + persistence) ==='
\echo '    order: rank_blast_radius + rank_persistence ascending (dense ranks over the corpus:'
\echo '    blast radius = distinct nodes affected, persistence = active days); ties by blast radius.'
\echo '    A ranking of measured factors, not an impact estimate. Last row: the loudest by lines.'
WITH ranked AS (
    SELECT *,
           row_number() OVER (ORDER BY rank_blast_radius + rank_persistence, rank_blast_radius, signature_id) AS risk_position,
           row_number() OVER (ORDER BY alert_lines DESC, signature_id)                                       AS lines_position
    FROM mgr_bgl_risk
)
SELECT risk_position, lines_position, signature_id, alert_category, component, team,
       nodes_affected, active_days, episodes_5min, alert_lines, top_node_pct,
       rank_blast_radius + rank_persistence AS rank_sum
FROM ranked
WHERE risk_position <= 5 OR lines_position = 1
ORDER BY risk_position;

\echo '=== M3 ownership: who owns the alert lines (no text) ==='
SELECT team, problem_lines AS alert_lines, pct_problem_lines AS pct_alert_lines
FROM ownership_coverage
WHERE dataset = 'BGL' AND problem_lines > 0
ORDER BY problem_lines DESC;
\echo '    Not established by the logs: cost, downtime, impact on jobs or users, root cause.'
RESET ROLE;

\echo ''
\echo '################################################################################'
\echo '# W2 (OpenStack): "Were the instances that were supposed to be slow actually slow?"'
\echo '################################################################################'

SET ROLE exhibit_engineer;
\echo ''
\echo '=== scope (describe_data) ==='
SELECT 'OpenStack' AS dataset, count(*) AS lines, count(DISTINCT nullif(instance_id, 'NONE')) AS instances,
       min(ts) AS first_ts, max(ts) AS last_ts
FROM os_ev;

\echo ''
\echo '--- W2 engineer -----------------------------------------------------------------'
\echo '=== E1 durations(metric = api_latency_s, group_by = file): normal vs abnormal ==='
SELECT file_group, api_calls, round(mean_s, 4) AS mean_s, round(p50_s, 4) AS p50_s,
       round(p95_s, 4) AS p95_s, round(p99_s, 4) AS p99_s
FROM os_latency_by_file
WHERE source_file = 'ALL'
ORDER BY file_group;

\echo '=== E2 count_events(group_by = level): the whole error surface ==='
SELECT level, count(*) AS lines
FROM os_ev
GROUP BY level
ORDER BY lines DESC;
RESET ROLE;

\echo ''
\echo '--- W2 team lead -----------------------------------------------------------------'
SET ROLE exhibit_lead;
\echo '=== L1 durations(metric = spawn_s, rank): slowest instances to spawn ==='
SELECT row_number() OVER (ORDER BY spawn_s DESC NULLS LAST, instance_id) AS position,
       instance_id, spawn_s, image_s, boot_s, source_file
FROM os_instance_durations
ORDER BY position
LIMIT 5;

\echo '=== L2 durations(metric = phases): medians over every instance with both ends ==='
SELECT count(spawn_s) AS spawned,
       round(quantile_cont(spawn_s, 0.5), 2) AS spawn_p50_s,
       round(quantile_cont(image_s, 0.5), 3) AS image_p50_s,
       round(quantile_cont(boot_s, 0.5), 3)  AS boot_p50_s
FROM os_instance_durations;

\echo '=== L3 top_signatures(dataset = OpenStack) with ownership: problems above INFO ==='
SELECT problem, team, worst_level, episodes AS incidents_5min, records, tracebacks, lines
FROM os_problem_incidents
ORDER BY worst_rank DESC, episodes DESC, problem;
RESET ROLE;

\echo ''
\echo '--- W2 manager (no log text, no instance IDs) ------------------------------------'
SET ROLE exhibit_manager;
\echo '=== M1 top_signatures: problems by severity and incidents (gap 5 min) ==='
SELECT problem, service, team, worst_level, incidents_5min, records, tracebacks, lines,
       critical_lines, error_lines, warning_lines
FROM mgr_os_risk
ORDER BY critical_lines DESC, error_lines DESC, incidents_5min DESC, problem;

\echo '=== M2 durations: spawn time distribution, normal vs abnormal file ==='
SELECT file_group, spawned, round(spawn_p50_s, 2) AS spawn_p50_s, round(spawn_p95_s, 2) AS spawn_p95_s,
       round(spawn_max_s, 2) AS spawn_max_s, round(image_p50_s, 3) AS image_p50_s,
       round(image_max_s, 3) AS image_max_s
FROM mgr_os_lifecycle
ORDER BY file_group;
\echo '    Not established by the logs: how the anomalies were injected, user impact, cost.'
RESET ROLE;

\echo ''
\echo '################################################################################'
\echo '# VALIDATION (outside the agent: no tool or role view reads the labels)'
\echo '################################################################################'
\echo '=== W2: where the 4 instances of anomaly_labels.txt land in the spawn ranking ==='
WITH ranked AS (
    SELECT instance_id, spawn_s,
           row_number() OVER (ORDER BY spawn_s DESC NULLS LAST, instance_id) AS position
    FROM os_instance_durations
)
SELECT position, instance_id, spawn_s,
       instance_id IN ('544fd51c-4edc-4780-baae-ba1d80a0acfc',
                       'ae651dff-c7ad-43d6-ac96-bbcd820ccca8',
                       'a445709b-6ad0-40ec-8860-bec60b6ca0c2',
                       '1643649d-2f42-4303-bfcd-7798baec19f9') AS is_labelled_anomaly
FROM ranked
WHERE position <= 5
ORDER BY position;
