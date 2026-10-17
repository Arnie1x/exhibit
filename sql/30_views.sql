-- sql/30_views.sql
-- Signature, episode, incident and role views.
--
-- All of these read the PLAIN derived tables (bgl_ev / os_ev). Views must never contain
-- `@@` -- that operator only works against an index relation (bgl_idx / os_idx), which is
-- why the lifecycle matchers below use LIKE/regexp instead.

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------- signatures
-- A signature is the message with machine-specific data masked out, so that the same fault
-- on two different nodes collapses to one row. Order matters: UUIDs first, then any digits.
-- signature_id (12 hex of md5(signature)) names a signature without its text: the manager
-- views in sql/50_roles.sql carry the id, never the text.
DROP VIEW IF EXISTS bgl_sig CASCADE;
CREATE VIEW bgl_sig AS
SELECT
    id, ts, alert_category, is_alert, node, node_kind, rack, midplane, nodecard,
    component, level, level_rank, team,
    signature, left(md5(signature), 12)        AS signature_id,
    content
FROM (
    SELECT *,
           regexp_replace(
             regexp_replace(content,
               '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
               '{uuid}', 'g'),
             '[0-9]+', '{n}', 'g')              AS signature
    FROM bgl_ev
) masked;

-- os_sig also carries what W2 needs, all derived from columns or the masked signature:
--   level_rank  CRITICAL 4 > ERROR 3 > WARNING 2 > INFO 1.
--   record_key  one log record: a Python traceback is ~23 lines with the same file, pid, ts,
--               logger and level, so its lines share one key (184 ERROR lines = 8 records).
--   problem     our label for every line above INFO, from logger and level; 'NONE' for INFO.
--               Labels are ours, not log text, so the manager views may carry them.
--   event       instance lifecycle step, matched on the exact masked signature.
--   took_s      the N in "Took N seconds to ..." (spawn, build, destroy, deallocate).
DROP VIEW IF EXISTS os_sig CASCADE;
CREATE VIEW os_sig AS
SELECT
    id, ts, source_file, service, logger, level, level_rank, pid, req_id, tenant_id, instance_id,
    http_method, endpoint, status, resp_len, latency_s, spawn_s, build_s, team,
    signature, left(md5(signature), 12)        AS signature_id,
    concat_ws('|', source_file, pid::VARCHAR, ts::VARCHAR, logger, level) AS record_key,
    CASE
        WHEN level = 'INFO'                                                  THEN 'NONE'
        WHEN logger = 'oslo_service.periodic_task' AND level = 'ERROR'       THEN 'image cache pass failed (InvalidDiskInfo)'
        WHEN logger = 'nova.virt.libvirt.imagecache' AND level = 'WARNING'   THEN 'image cache: unknown base file'
        WHEN logger = 'keystonemiddleware.auth_token'                        THEN 'token validation failed (identity server 503)'
        WHEN logger = 'nova.compute.manager' AND level = 'WARNING'           THEN 'power-state sync: instance count mismatch'
        WHEN logger = 'nova.virt.libvirt.driver' AND level = 'WARNING'       THEN 'vcpu count unavailable (cpu affinity)'
        ELSE 'UNCLASSIFIED: ' || service
    END                                         AS problem,
    CASE signature
        WHEN '[instance: {uuid}] Attempting claim: memory {n} MB, disk {n} GB, vcpus {n} CPU'      THEN 'claim_start'
        WHEN '[instance: {uuid}] Claim successful'                                                 THEN 'claimed'
        WHEN '[instance: {uuid}] Creating image'                                                   THEN 'image_create'
        WHEN '[instance: {uuid}] VM Started (Lifecycle Event)'                                     THEN 'vm_started'
        WHEN '[instance: {uuid}] VM Paused (Lifecycle Event)'                                      THEN 'vm_paused'
        WHEN '[instance: {uuid}] VM Resumed (Lifecycle Event)'                                     THEN 'vm_resumed'
        WHEN '[instance: {uuid}] Instance spawned successfully.'                                   THEN 'spawned'
        WHEN '[instance: {uuid}] Took {n}.{n} seconds to spawn the instance on the hypervisor.'    THEN 'took_spawn'
        WHEN '[instance: {uuid}] Took {n}.{n} seconds to build instance.'                          THEN 'took_build'
        WHEN '[instance: {uuid}] Terminating instance'                                             THEN 'terminate'
        WHEN '[instance: {uuid}] Instance destroyed successfully.'                                 THEN 'destroyed'
        WHEN '[instance: {uuid}] Took {n}.{n} seconds to destroy the instance on the hypervisor.'  THEN 'took_destroy'
        WHEN '[instance: {uuid}] Took {n}.{n} seconds to deallocate network for instance.'         THEN 'took_dealloc'
        WHEN '[instance: {uuid}] VM Stopped (Lifecycle Event)'                                     THEN 'vm_stopped'
        ELSE 'NONE'
    END                                         AS event,
    TRY_CAST(nullif(regexp_extract(content, 'Took ([0-9.]+) seconds', 1), '') AS DOUBLE) AS took_s,
    content
FROM (
    SELECT *,
           CASE level WHEN 'CRITICAL' THEN 4 WHEN 'ERROR' THEN 3
                      WHEN 'WARNING'  THEN 2 WHEN 'INFO'  THEN 1 ELSE 0 END AS level_rank,
           regexp_replace(
             regexp_replace(content,
               '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
               '{uuid}', 'g'),
             '[0-9]+', '{n}', 'g')              AS signature
    FROM os_ev
) masked;

-- ---------------------------------------------------------------- episodes
-- THE CORE FINDING: an incident is not a line. A new episode starts when the same
-- signature goes quiet for more than 5 minutes in the same failure domain (midplane).
DROP VIEW IF EXISTS bgl_episode CASCADE;
CREATE VIEW bgl_episode AS
WITH marked AS (
    SELECT *,
           CASE WHEN LAG(ts) OVER (PARTITION BY signature, midplane ORDER BY ts) IS NULL
                  OR ts - LAG(ts) OVER (PARTITION BY signature, midplane ORDER BY ts)
                     > INTERVAL '5 minutes'
                THEN 1 ELSE 0 END AS is_new_episode
    FROM bgl_sig
    WHERE is_alert
)
SELECT *, SUM(is_new_episode) OVER (PARTITION BY signature, midplane
                                    ORDER BY ts ROWS UNBOUNDED PRECEDING) AS episode_no
FROM marked;

-- one row per incident, with the blast radius the line count hides
DROP VIEW IF EXISTS bgl_incident CASCADE;
CREATE VIEW bgl_incident AS
SELECT
    signature_id, signature, midplane, episode_no,
    count(*)                    AS lines,
    count(DISTINCT node)        AS nodes,
    min(ts)                     AS started,
    max(ts)                     AS ended,
    max(ts) - min(ts)           AS span,
    max(level_rank)             AS worst_rank,
    min(component)              AS component,
    min(team)                   AS team
FROM bgl_episode
GROUP BY signature_id, signature, midplane, episode_no;

-- per-signature rollup: lines vs peak blast radius vs episode count
DROP VIEW IF EXISTS bgl_signature_incidents CASCADE;
CREATE VIEW bgl_signature_incidents AS
SELECT
    signature_id, signature,
    count(*)        AS episodes,
    sum(lines)      AS lines,
    max(nodes)      AS peak_nodes,
    max(worst_rank) AS worst_rank,
    min(team)       AS team,
    min(started)    AS first_seen,
    max(ended)      AS last_seen
FROM bgl_incident
GROUP BY signature_id, signature;

-- Every ranking factor per alert signature, whole corpus: the source of top_signatures
-- (rank_by lines | episodes | nodes | blast radius | persistence) and of mgr_bgl_risk, which
-- is this view without the signature text and the node ID.
--   blast radius  nodes_affected: distinct nodes that ever logged the signature
--   persistence   active_days: distinct calendar days with at least one line
--   concentration top_node_pct: percent of the lines from the single loudest node
-- rank_blast_radius / rank_persistence are dense ranks over the whole corpus (1 = widest,
-- most persistent); a time-windowed ranking has to recompute them, not filter this view.
DROP VIEW IF EXISTS bgl_signature_stats CASCADE;
CREATE VIEW bgl_signature_stats AS
WITH l AS (
    SELECT
        signature_id, signature,
        mode(alert_category)            AS alert_category,
        mode(component)                 AS component,
        mode(team)                      AS team,
        arg_max(level, level_rank)      AS worst_level,
        count(*)                        AS alert_lines,
        count(DISTINCT node)            AS nodes_affected,
        count(DISTINCT midplane)        AS midplanes_affected,
        count(DISTINCT ts::date)        AS active_days,
        min(ts)                         AS first_seen,
        max(ts)                         AS last_seen
    FROM bgl_sig
    WHERE is_alert
    GROUP BY signature_id, signature
), n AS (
    -- loudest node per signature; ties go to the lower node ID so reruns agree
    SELECT signature_id, node AS top_node, lines AS top_node_lines
    FROM (
        SELECT signature_id, node, count(*) AS lines,
               row_number() OVER (PARTITION BY signature_id ORDER BY count(*) DESC, node) AS rn
        FROM bgl_sig
        WHERE is_alert
        GROUP BY signature_id, node
    ) per_node
    WHERE rn = 1
), e AS (
    SELECT
        signature_id,
        count(*)                        AS episodes_5min,
        max(nodes)                      AS peak_nodes_per_episode,
        max(span)                       AS longest_episode
    FROM bgl_incident
    GROUP BY signature_id
)
SELECT
    'BGL' AS dataset, l.signature_id, l.signature, l.alert_category, l.component, l.team,
    l.worst_level, l.alert_lines, e.episodes_5min, l.nodes_affected, l.midplanes_affected,
    e.peak_nodes_per_episode, l.active_days, e.longest_episode,
    n.top_node, n.top_node_lines,
    round(100 * n.top_node_lines::DOUBLE / l.alert_lines, 2)      AS top_node_pct,
    dense_rank() OVER (ORDER BY l.nodes_affected DESC)             AS rank_blast_radius,
    dense_rank() OVER (ORDER BY l.active_days DESC)                AS rank_persistence,
    l.first_seen, l.last_seen
FROM l
JOIN e USING (signature_id)
JOIN n USING (signature_id);

-- Episode counts at the three stated gaps, per alert signature, at both scopes: per failure
-- domain (signature x midplane, the bgl_episode definition) and global (signature only).
-- A gap counts as a new episode when it is longer than the threshold; equal timestamps give a
-- zero gap, so the counts do not depend on how ties are ordered. Sums over all signatures:
-- 19,250 (5 min, midplane) and 1,377 (5 min, global), the make smoke §2 numbers.
DROP VIEW IF EXISTS bgl_episode_sensitivity CASCADE;
CREATE VIEW bgl_episode_sensitivity AS
WITH gaps AS (
    SELECT
        signature_id, signature,
        ts - LAG(ts) OVER (PARTITION BY signature, midplane ORDER BY ts) AS gap_domain,
        ts - LAG(ts) OVER (PARTITION BY signature ORDER BY ts)           AS gap_global
    FROM bgl_sig
    WHERE is_alert
)
SELECT
    signature_id, signature,
    count(*)                                                                         AS alert_lines,
    count(*) FILTER (WHERE gap_domain IS NULL OR gap_domain > INTERVAL '1 minute')   AS episodes_1min,
    count(*) FILTER (WHERE gap_domain IS NULL OR gap_domain > INTERVAL '5 minutes')  AS episodes_5min,
    count(*) FILTER (WHERE gap_domain IS NULL OR gap_domain > INTERVAL '60 minutes') AS episodes_60min,
    count(*) FILTER (WHERE gap_global IS NULL OR gap_global > INTERVAL '1 minute')   AS episodes_1min_global,
    count(*) FILTER (WHERE gap_global IS NULL OR gap_global > INTERVAL '5 minutes')  AS episodes_5min_global,
    count(*) FILTER (WHERE gap_global IS NULL OR gap_global > INTERVAL '60 minutes') AS episodes_60min_global
FROM gaps
GROUP BY signature_id, signature;

-- ---------------------------------------------------------------- OpenStack incidents
-- Same idea as BGL, one level up: lines above INFO, grouped by problem; a new incident starts
-- when the problem goes quiet for more than 5 minutes. A traceback's ~23 lines share one ts,
-- so it is one record inside one incident, never 23 problems.
DROP VIEW IF EXISTS os_episode CASCADE;
CREATE VIEW os_episode AS
WITH marked AS (
    SELECT *,
           CASE WHEN LAG(ts) OVER (PARTITION BY problem ORDER BY ts, id) IS NULL
                  OR ts - LAG(ts) OVER (PARTITION BY problem ORDER BY ts, id)
                     > INTERVAL '5 minutes'
                THEN 1 ELSE 0 END AS is_new_episode
    FROM os_sig
    WHERE level <> 'INFO'
)
SELECT *, SUM(is_new_episode) OVER (PARTITION BY problem
                                    ORDER BY ts, id ROWS UNBOUNDED PRECEDING) AS episode_no
FROM marked;

-- one row per OpenStack incident
DROP VIEW IF EXISTS os_incident CASCADE;
CREATE VIEW os_incident AS
SELECT
    problem, episode_no,
    count(*)                                                        AS lines,
    count(DISTINCT record_key)                                      AS records,
    count(*) FILTER (WHERE signature = 'Traceback (most recent call last):') AS tracebacks,
    count(*) FILTER (WHERE level = 'CRITICAL')                      AS critical_lines,
    count(*) FILTER (WHERE level = 'ERROR')                         AS error_lines,
    count(*) FILTER (WHERE level = 'WARNING')                       AS warning_lines,
    count(DISTINCT nullif(req_id, 'NONE'))                          AS requests,
    count(DISTINCT nullif(instance_id, 'NONE'))                     AS instances,
    max(level_rank)                                                 AS worst_rank,
    arg_max(level, level_rank)                                      AS worst_level,
    min(ts)                                                         AS started,
    max(ts)                                                         AS ended,
    max(ts) - min(ts)                                               AS span,
    mode(service)                                                   AS service,
    mode(team)                                                      AS team,
    mode(source_file)                                               AS source_file
FROM os_episode
GROUP BY problem, episode_no;

-- per-problem rollup: lines vs incidents vs records, side by side
DROP VIEW IF EXISTS os_problem_incidents CASCADE;
CREATE VIEW os_problem_incidents AS
SELECT
    problem,
    count(*)            AS episodes,
    sum(records)        AS records,
    sum(tracebacks)     AS tracebacks,
    sum(lines)          AS lines,
    sum(critical_lines) AS critical_lines,
    sum(error_lines)    AS error_lines,
    sum(warning_lines)  AS warning_lines,
    sum(requests)       AS requests,
    max(worst_rank)     AS worst_rank,
    arg_max(worst_level, worst_rank) AS worst_level,
    mode(service)       AS service,
    mode(team)          AS team,
    min(started)        AS first_seen,
    max(ended)          AS last_seen
FROM os_incident
GROUP BY problem;

-- ---------------------------------------------------------------- OpenStack durations
-- The labelled anomalies are invisible to any level filter or latency percentile; they
-- only show up as lifecycle-duration outliers per instance. Phases, in seconds, from the
-- lifecycle events in os_sig (NULL when an instance lacks either end):
--   claim_s     Attempting claim -> Claim successful
--   image_s     Creating image   -> VM Started
--   boot_s      VM Started       -> Instance spawned successfully
--   run_s       spawned          -> Terminating instance
--   teardown_s  Terminating      -> VM Stopped
-- spawn_s, build_s, destroy_s, dealloc_s are nova's own "Took N seconds" figures.
DROP VIEW IF EXISTS os_instance_durations CASCADE;
CREATE VIEW os_instance_durations AS
WITH p AS (
    SELECT
        instance_id,
        count(*)                                                    AS lines,
        max(spawn_s)                                                AS spawn_s,
        max(build_s)                                                AS build_s,
        max(took_s) FILTER (WHERE event = 'took_destroy')           AS destroy_s,
        max(took_s) FILTER (WHERE event = 'took_dealloc')           AS dealloc_s,
        min(ts) FILTER (WHERE event = 'claim_start')                AS t_claim,
        min(ts) FILTER (WHERE event = 'claimed')                    AS t_claimed,
        min(ts) FILTER (WHERE event = 'image_create')               AS t_image,
        min(ts) FILTER (WHERE event = 'vm_started')                 AS t_started,
        min(ts) FILTER (WHERE event = 'spawned')                    AS t_spawned,
        min(ts) FILTER (WHERE event = 'terminate')                  AS t_terminate,
        max(ts) FILTER (WHERE event = 'vm_stopped')                 AS t_stopped,
        min(ts)                                                     AS first_seen,
        max(ts)                                                     AS last_seen,
        mode(source_file)                                           AS source_file,
        mode(team)                                                  AS team
    FROM os_sig
    WHERE instance_id <> 'NONE'
    GROUP BY instance_id
)
SELECT
    instance_id, lines, spawn_s, build_s, destroy_s, dealloc_s,
    round(extract(epoch FROM t_claimed   - t_claim),     3)       AS claim_s,
    round(extract(epoch FROM t_started   - t_image),     3)       AS image_s,
    round(extract(epoch FROM t_spawned   - t_started),   3)       AS boot_s,
    round(extract(epoch FROM t_terminate - t_spawned),   3)       AS run_s,
    round(extract(epoch FROM t_stopped   - t_terminate), 3)       AS teardown_s,
    first_seen, last_seen,
    last_seen - first_seen                                          AS lifetime,
    round(extract(epoch FROM last_seen - first_seen), 3)            AS lifetime_s,
    source_file, team
FROM p;

-- API latency per log file: the engineer's check that the abnormal file is not slower.
-- Percentiles are quantile_cont (linear interpolation, = percentile_cont).
DROP VIEW IF EXISTS os_latency_by_file CASCADE;
CREATE VIEW os_latency_by_file AS
SELECT
    file_group,
    coalesce(source_file, 'ALL')                    AS source_file,
    count(*)                                        AS api_calls,
    avg(latency_s)                                  AS mean_s,
    quantile_cont(latency_s, 0.50)                  AS p50_s,
    quantile_cont(latency_s, 0.95)                  AS p95_s,
    quantile_cont(latency_s, 0.99)                  AS p99_s,
    max(latency_s)                                  AS max_s,
    count(*) FILTER (WHERE status = 404)            AS http_404,
    count(*) FILTER (WHERE status >= 500)           AS http_5xx
FROM (
    SELECT *, CASE WHEN source_file = 'openstack_abnormal.log' THEN 'abnormal' ELSE 'normal' END AS file_group
    FROM os_sig
    WHERE latency_s IS NOT NULL
) l
GROUP BY GROUPING SETS ((file_group, source_file), (file_group));

-- ---------------------------------------------------------------- ownership
-- Lines per owning team and dataset, with the key that assigned the team (precedence
-- logger > service > component, data/ownership.csv) and 'none' for UNOWNED. problem_lines is
-- BGL alert lines (label <> '-') or OpenStack lines above INFO. A team can span two rows on
-- OpenStack (logger and service matches): sum them for the team's share.
DROP VIEW IF EXISTS ownership_coverage CASCADE;
CREATE VIEW ownership_coverage AS
SELECT
    dataset, team, matched_on, lines, problem_lines,
    round(100 * lines::DOUBLE / sum(lines) OVER (PARTITION BY dataset), 2)                       AS pct_lines,
    round(100 * problem_lines::DOUBLE / nullif(sum(problem_lines) OVER (PARTITION BY dataset), 0), 2) AS pct_problem_lines
FROM (
    SELECT 'BGL' AS dataset, team,
           CASE WHEN team = 'UNOWNED' THEN 'none' ELSE 'component' END AS matched_on,
           count(*) AS lines, count(*) FILTER (WHERE is_alert) AS problem_lines
    FROM bgl_ev
    GROUP BY team
    UNION ALL
    SELECT 'OpenStack', e.team,
           CASE WHEN ol.team IS NOT NULL THEN 'logger'
                WHEN e.team <> 'UNOWNED' THEN 'service'
                ELSE 'none' END,
           count(*), count(*) FILTER (WHERE e.level <> 'INFO')
    FROM os_ev e
    LEFT JOIN owner_map ol
           ON ol.dataset = 'OpenStack' AND ol.key_type = 'logger' AND ol.key_value = e.logger
    GROUP BY 1, 2, 3
) t;
