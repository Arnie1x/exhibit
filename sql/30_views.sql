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

DROP VIEW IF EXISTS os_sig CASCADE;
CREATE VIEW os_sig AS
SELECT
    id, ts, source_file, service, logger, level, pid, req_id, tenant_id, instance_id,
    http_method, endpoint, status, resp_len, latency_s, spawn_s, build_s, team,
    signature, left(md5(signature), 12)        AS signature_id,
    content
FROM (
    SELECT *,
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

-- ---------------------------------------------------------------- OpenStack durations
-- The labelled anomalies are invisible to any level filter or latency percentile; they
-- only show up as lifecycle-duration outliers per instance.
DROP VIEW IF EXISTS os_instance_durations CASCADE;
CREATE VIEW os_instance_durations AS
SELECT
    instance_id,
    count(*)                                                       AS lines,
    max(spawn_s)                                                    AS spawn_s,
    max(build_s)                                                    AS build_s,
    min(ts)                                                         AS first_seen,
    max(ts)                                                         AS last_seen,
    max(ts) - min(ts)                                               AS lifetime,
    'NONE'                                                          AS team
FROM os_ev
WHERE instance_id <> 'NONE'
GROUP BY instance_id;
