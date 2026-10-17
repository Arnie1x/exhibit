-- sql/50_roles.sql
-- Role scope enforced in the database: three roles, each holding SELECT on its own views.
--
-- SereneDB 26.09.1.3 has no row-level security, so scope is which relations a role can read
-- (docs/capabilities.md §6, team plan §16 rules 12-14, all measured):
--   * GRANT cannot target an index relation, and a query on bgl_idx is checked against bgl_ev:
--     a role with SELECT on bgl_ev can search bgl_idx by name, a role without it cannot.
--   * A view reads its sources with its owner's (postgres's) privileges, so a role holding only
--     a view sees exactly that view's columns, and search through a view over bgl_idx works.
--   * SECURITY DEFINER is not honoured; CREATE ROLE IF NOT EXISTS and DROP OWNED BY do not
--     exist; GRANT takes one table per statement. So roles are created once (psql \if) and never
--     dropped, and the role views are dropped and recreated on every run, which drops their
--     grants with them.
--
--   exhibit_engineer  raw lines, highlights, timelines, neighbours: SELECT on bgl_ev, os_ev
--                     (so bgl_idx / os_idx are searchable by name), owner_map and every view.
--   exhibit_lead      signatures by owning team, trends, incidents, durations: lead_* rollups
--                     and the incident views. No per-line relation, no content, no search.
--   exhibit_manager   risks by blast radius and persistence with the affected component (BGL) or
--                     service (OpenStack) and the owning team: mgr_* views. No log text (neither
--                     content nor signature text: a BGL problem is a signature_id plus its alert
--                     category, an OpenStack problem is our label from sql/30_views.sql), no node
--                     IDs, no logger names, no instance IDs.
--
-- Roles are LOGIN without a password, so they cannot log in on their own: SereneDB trusts only
-- postgres on loopback and refuses a password-less role everywhere (docs/capabilities.md §6).
-- Connect as postgres and SET ROLE exhibit_<role>, as the scope proof below and
-- sql/90_queries.sql do. Never put a password in this file.
--
-- Run after sql/30_views.sql, whose DROP ... CASCADE removes these views (make bootstrap does):
--   psql -h 127.0.0.1 -p 7890 -U postgres -f sql/50_roles.sql

\set ON_ERROR_STOP on
-- GRANT / REVOKE / CREATE VIEW each print an empty "Success" result here; keep the output to
-- the scope proof at the end.
\o /dev/null

-- ---------------------------------------------------------------- roles (created once)
SELECT NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'exhibit_engineer') AS need_engineer,
       NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'exhibit_lead')     AS need_lead,
       NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'exhibit_manager')  AS need_manager
\gset
\if :need_engineer
CREATE ROLE exhibit_engineer LOGIN;
\endif
\if :need_lead
CREATE ROLE exhibit_lead LOGIN;
\endif
\if :need_manager
CREATE ROLE exhibit_manager LOGIN;
\endif

-- Start every run from no table-level grants (REVOKE of a privilege not held is a no-op), so a
-- grant removed from this file is also removed from the database.
REVOKE ALL ON bgl_ev    FROM exhibit_engineer;
REVOKE ALL ON os_ev     FROM exhibit_engineer;
REVOKE ALL ON owner_map FROM exhibit_engineer;
REVOKE ALL ON bgl_ev    FROM exhibit_lead;
REVOKE ALL ON os_ev     FROM exhibit_lead;
REVOKE ALL ON owner_map FROM exhibit_lead;
REVOKE ALL ON bgl_ev    FROM exhibit_manager;
REVOKE ALL ON os_ev     FROM exhibit_manager;
REVOKE ALL ON owner_map FROM exhibit_manager;

-- ---------------------------------------------------------------- engineer
GRANT SELECT ON bgl_ev                  TO exhibit_engineer;
GRANT SELECT ON os_ev                   TO exhibit_engineer;
GRANT SELECT ON owner_map               TO exhibit_engineer;
GRANT SELECT ON bgl_sig                 TO exhibit_engineer;
GRANT SELECT ON os_sig                  TO exhibit_engineer;
GRANT SELECT ON bgl_episode             TO exhibit_engineer;
GRANT SELECT ON bgl_incident            TO exhibit_engineer;
GRANT SELECT ON bgl_signature_incidents TO exhibit_engineer;
GRANT SELECT ON os_instance_durations   TO exhibit_engineer;
GRANT SELECT ON os_episode              TO exhibit_engineer;
GRANT SELECT ON os_incident             TO exhibit_engineer;
GRANT SELECT ON os_problem_incidents    TO exhibit_engineer;
GRANT SELECT ON os_latency_by_file      TO exhibit_engineer;
GRANT SELECT ON bgl_signature_stats     TO exhibit_engineer;
GRANT SELECT ON bgl_episode_sensitivity TO exhibit_engineer;
GRANT SELECT ON ownership_coverage      TO exhibit_engineer;

-- ---------------------------------------------------------------- lead
-- Per day (BGL, seven months) and per hour (OpenStack, 2.7 days). nodes / instances / requests
-- are distinct counts within the bucket: never sum them across buckets.
DROP VIEW IF EXISTS lead_bgl_daily;
CREATE VIEW lead_bgl_daily AS
SELECT
    ts::date                    AS day,
    team, component, level, alert_category, is_alert,
    signature_id, signature,
    count(*)                    AS lines,
    count(DISTINCT node)        AS nodes,
    count(DISTINCT midplane)    AS midplanes
FROM bgl_sig
GROUP BY ts::date, team, component, level, alert_category, is_alert, signature_id, signature;

DROP VIEW IF EXISTS lead_os_hourly;
CREATE VIEW lead_os_hourly AS
SELECT
    date_trunc('hour', ts)                          AS hour,
    team, service, logger, level,
    signature_id, signature,
    count(*)                                        AS lines,
    count(DISTINCT nullif(instance_id, 'NONE'))     AS instances,
    count(DISTINCT nullif(req_id, 'NONE'))          AS requests,
    count(*) FILTER (WHERE status >= 400)           AS http_errors
FROM os_sig
GROUP BY date_trunc('hour', ts), team, service, logger, level, signature_id, signature;

GRANT SELECT ON lead_bgl_daily          TO exhibit_lead;
GRANT SELECT ON lead_os_hourly          TO exhibit_lead;
GRANT SELECT ON bgl_incident            TO exhibit_lead;
GRANT SELECT ON bgl_signature_incidents TO exhibit_lead;
GRANT SELECT ON os_instance_durations   TO exhibit_lead;
GRANT SELECT ON os_incident             TO exhibit_lead;
GRANT SELECT ON os_problem_incidents    TO exhibit_lead;
GRANT SELECT ON os_latency_by_file      TO exhibit_lead;
GRANT SELECT ON owner_map               TO exhibit_lead;
GRANT SELECT ON bgl_signature_stats     TO exhibit_lead;
GRANT SELECT ON bgl_episode_sensitivity TO exhibit_lead;
GRANT SELECT ON ownership_coverage      TO exhibit_lead;
GRANT SELECT ON lead_bgl_daily          TO exhibit_engineer;
GRANT SELECT ON lead_os_hourly          TO exhibit_engineer;

-- ---------------------------------------------------------------- manager
-- One row per BGL alert signature: blast radius (nodes, midplanes, peak nodes in one episode),
-- persistence (episodes at the stated 5-minute gap, active days, first/last seen) and
-- concentration (top_node_pct). bgl_signature_stats without the signature text and node ID.
DROP VIEW IF EXISTS mgr_bgl_risk;
CREATE VIEW mgr_bgl_risk AS
SELECT
    dataset, signature_id, alert_category, component, team, worst_level,
    alert_lines, episodes_5min, nodes_affected, midplanes_affected,
    peak_nodes_per_episode, active_days, longest_episode, top_node_pct,
    rank_blast_radius, rank_persistence, first_seen, last_seen
FROM bgl_signature_stats;

-- One row per OpenStack problem (our label, not log text) above INFO: incidents at the stated
-- 5-minute gap, records (a traceback is one), lines by level, requests. Lifecycle-duration
-- outliers (the labelled anomalies are INFO-only) are in mgr_os_lifecycle, not here.
DROP VIEW IF EXISTS mgr_os_risk;
CREATE VIEW mgr_os_risk AS
SELECT
    'OpenStack' AS dataset, problem, service, team, worst_level,
    episodes AS incidents_5min, records, tracebacks, lines,
    critical_lines, error_lines, warning_lines,
    requests AS requests_affected, first_seen, last_seen
FROM os_problem_incidents;

-- Instance lifecycle durations as a distribution, without instance IDs.
DROP VIEW IF EXISTS mgr_os_lifecycle;
CREATE VIEW mgr_os_lifecycle AS
SELECT
    CASE WHEN source_file = 'openstack_abnormal.log' THEN 'abnormal' ELSE 'normal' END AS file_group,
    count(*)                            AS instances,
    count(spawn_s)                      AS spawned,
    quantile_cont(spawn_s, 0.50)        AS spawn_p50_s,
    quantile_cont(spawn_s, 0.95)        AS spawn_p95_s,
    max(spawn_s)                        AS spawn_max_s,
    quantile_cont(image_s, 0.50)        AS image_p50_s,
    max(image_s)                        AS image_max_s,
    quantile_cont(boot_s, 0.50)         AS boot_p50_s,
    max(boot_s)                         AS boot_max_s
FROM os_instance_durations
GROUP BY 1;

-- Whole-corpus totals per day, both datasets: component = BGL component or OpenStack service;
-- category = BGL alert category ('-' = unlabelled) or 'NONE' for OpenStack.
DROP VIEW IF EXISTS mgr_rollup_daily;
CREATE VIEW mgr_rollup_daily AS
SELECT 'BGL' AS dataset, ts::date AS day, team, component, alert_category AS category, level,
       count(*) AS lines
FROM bgl_ev
GROUP BY ts::date, team, component, alert_category, level
UNION ALL
SELECT 'OpenStack', ts::date, team, service, 'NONE', level, count(*)
FROM os_ev
GROUP BY ts::date, team, service, level;

GRANT SELECT ON mgr_bgl_risk     TO exhibit_manager;
GRANT SELECT ON mgr_os_risk      TO exhibit_manager;
GRANT SELECT ON mgr_os_lifecycle TO exhibit_manager;
GRANT SELECT ON mgr_os_lifecycle TO exhibit_lead;
GRANT SELECT ON mgr_os_lifecycle TO exhibit_engineer;
GRANT SELECT ON mgr_rollup_daily TO exhibit_manager;
-- ownership_coverage holds teams, key types and counts only: no text, no node or logger names
GRANT SELECT ON ownership_coverage TO exhibit_manager;
GRANT SELECT ON mgr_bgl_risk     TO exhibit_lead;
GRANT SELECT ON mgr_os_risk      TO exhibit_lead;
GRANT SELECT ON mgr_rollup_daily TO exhibit_lead;
GRANT SELECT ON mgr_bgl_risk     TO exhibit_engineer;
GRANT SELECT ON mgr_os_risk      TO exhibit_engineer;
GRANT SELECT ON mgr_rollup_daily TO exhibit_engineer;

-- ---------------------------------------------------------------- scope proof
\o
\echo '--- role scope: what each role can read (counts through its own views) ---'
SET ROLE exhibit_engineer;
SELECT 'engineer' AS role, (SELECT count(*) FROM bgl_idx WHERE content @@ 'ciod') AS bgl_idx_ciod,
       (SELECT count(*) FROM os_ev) AS os_ev_rows;
RESET ROLE;
SET ROLE exhibit_lead;
SELECT 'lead' AS role, (SELECT sum(lines) FROM lead_bgl_daily) AS bgl_lines,
       (SELECT sum(lines) FROM lead_os_hourly) AS os_lines,
       (SELECT sum(episodes_5min) FROM bgl_episode_sensitivity) AS bgl_episodes_5min,
       (SELECT sum(episodes_5min_global) FROM bgl_episode_sensitivity) AS bgl_episodes_5min_global;
RESET ROLE;
SET ROLE exhibit_manager;
SELECT 'manager' AS role, (SELECT sum(alert_lines) FROM mgr_bgl_risk) AS bgl_alert_lines,
       (SELECT sum(episodes_5min) FROM mgr_bgl_risk) AS bgl_episodes_5min,
       (SELECT sum(lines) FROM mgr_rollup_daily) AS all_lines,
       (SELECT sum(incidents_5min) FROM mgr_os_risk) AS os_incidents_5min,
       (SELECT sum(lines) FROM ownership_coverage) AS owned_lines;
RESET ROLE;

\echo '--- role scope: each statement below MUST fail with permission denied ---'
\set ON_ERROR_STOP off
SET ROLE exhibit_lead;
SELECT content FROM bgl_ev LIMIT 1;
SELECT count(*) FROM bgl_idx WHERE content @@ 'ciod';
RESET ROLE;
SET ROLE exhibit_manager;
SELECT content FROM bgl_ev LIMIT 1;
SELECT signature FROM lead_bgl_daily LIMIT 1;
SELECT count(*) FROM bgl_incident;
SELECT signature FROM bgl_signature_stats LIMIT 1;
RESET ROLE;
\set ON_ERROR_STOP on
