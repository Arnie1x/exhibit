-- sql/10_derive.sql
-- Derived, search-ready tables from the raw Loghub Parquet.
--
-- PATTERN B (decided 17 Oct): these are PLAIN tables. Full-text search NEVER runs against
-- them -- `@@` against a plain table fails with
--   "TSQUERY expression evaluated outside an `@@` match against an inverted-indexed column."
-- Search runs against the index relations bgl_idx / os_idx created by sql/20_indexes.sql.
-- Aggregations, trends and episode maths run against bgl_ev / os_ev.
--
-- Ownership: Unmapped keys become 'UNOWNED'. Sentinel 'UNKNOWN'/'NONE' instead of NULL,
-- because facet and keyword columns must be NOT NULL (GROUP BY on the term dictionary).
--
-- Run:
--   psql -h 127.0.0.1 -p 7890 -U postgres -v data=/data/loghub -v map=/data/ownership.csv \
--        -f sql/10_derive.sql

\set ON_ERROR_STOP on
\timing on
SET preserve_insertion_order = true;

-- ---------------------------------------------------------------- ownership map
DROP TABLE IF EXISTS owner_map CASCADE;
CREATE TABLE owner_map AS
SELECT dataset, key_type, key_value, team
FROM read_csv(:'map', header = true, auto_detect = true);

-- ---------------------------------------------------------------- BGL
DROP TABLE IF EXISTS bgl_ev CASCADE;
CREATE TABLE bgl_ev AS
SELECT
    row_number() OVER ()                                        AS id,
    b."timestamp"::timestamp                                    AS ts,
    coalesce(nullif(b.label, ''), 'UNKNOWN')                    AS alert_category,
    (b.label <> '-')                                            AS is_alert,
    b.node,
    CASE
        WHEN b.node LIKE '%-C:%'              THEN 'COMPUTE'
        WHEN b.node LIKE '%-I:%'              THEN 'IO'
        WHEN b.node LIKE '%-L%'               THEN 'LINK'
        WHEN b.node IN ('-', 'NULL', 'UNKNOWN_LOCATION') THEN 'UNKNOWN'
        ELSE 'OTHER'
    END                                                         AS node_kind,
    CASE
        WHEN b.node LIKE '%-%' THEN split_part(b.node, '-', 1)
        ELSE 'UNKNOWN'
    END                                                         AS rack,
    CASE
        WHEN b.node LIKE '%-%-%' THEN split_part(b.node, '-', 1) || '-' || split_part(b.node, '-', 2)
        ELSE 'UNKNOWN'
    END                                                         AS midplane,
    CASE
        WHEN b.node LIKE '%-%-%-%' THEN split_part(b.node, '-', 3)
        ELSE 'UNKNOWN'
    END                                                         AS nodecard,
    coalesce(nullif(b.component, ''), 'UNKNOWN')                AS component,
    coalesce(nullif(b.level, ''), 'UNKNOWN')                    AS level,
    CASE b.level
        WHEN 'INFO'    THEN 1
        WHEN 'WARNING' THEN 2
        WHEN 'SEVERE'  THEN 3
        WHEN 'ERROR'   THEN 4
        WHEN 'FAILURE' THEN 5
        WHEN 'FATAL'   THEN 5
        WHEN 'Kill'    THEN 5
        ELSE 0
    END                                                         AS level_rank,
    'UNKNOWN'                                                   AS template_id,
    coalesce(o.team, 'UNOWNED')                                 AS team,
    b.content
FROM read_parquet(:'data' || '/bgl.parquet') b
LEFT JOIN owner_map o
       ON o.dataset = 'BGL' AND o.key_type = 'component' AND o.key_value = b.component;

-- ---------------------------------------------------------------- OpenStack
DROP TABLE IF EXISTS os_ev CASCADE;
CREATE TABLE os_ev AS
SELECT
    row_number() OVER ()                                        AS id,
    "timestamp"::timestamp                                      AS ts,
    origin_file                                                  AS source_file,
    coalesce(nullif(service, ''), 'UNKNOWN')                     AS service,
    coalesce(nullif(logger, ''), 'UNKNOWN')                      AS logger,
    coalesce(nullif(level, ''), 'UNKNOWN')                       AS level,
    pid,
    coalesce(nullif(request_id, ''), 'NONE')                     AS req_id,
    coalesce(nullif(user_id, ''), 'NONE')                        AS user_id,
    coalesce(nullif(tenant_id, ''), 'NONE')                      AS tenant_id,
    coalesce(nullif(instance_id, ''), 'NONE')                    AS instance_id,
    coalesce(regexp_extract(b.message, '"([A-Z]+) /', 1), '')    AS http_method,
    regexp_replace(
      regexp_replace(
        regexp_extract(b.message, '"[A-Z]+ ([^ ]+) HTTP', 1),
        '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '{id}', 'g'),
      '[0-9a-f]{32}', '{tenant}', 'g')                           AS endpoint,
    status_code                                                  AS status,
    TRY_CAST(regexp_extract(b.message, 'len: ([0-9]+)', 1) AS INTEGER) AS resp_len,
    latency_s,
    TRY_CAST(regexp_extract(b.message, 'Took ([0-9.]+) seconds to spawn', 1) AS DOUBLE) AS spawn_s,
    TRY_CAST(regexp_extract(b.message, 'Took ([0-9.]+) seconds to build', 1) AS DOUBLE) AS build_s,
    coalesce(ol.team, os.team, 'UNOWNED')                        AS team,
    b.message AS content
FROM read_parquet(:'data' || '/openstack.parquet') b
LEFT JOIN owner_map ol
       ON ol.dataset = 'OpenStack' AND ol.key_type = 'logger'  AND ol.key_value = b.logger
LEFT JOIN owner_map os
       ON os.dataset = 'OpenStack' AND os.key_type = 'service' AND os.key_value = b.service;

\echo '--- derived ---'
SELECT 'BGL'       AS table_name, count(*) AS rows, count(*) FILTER (WHERE team = 'UNOWNED') AS unowned FROM bgl_ev
UNION ALL
SELECT 'OpenStack', count(*), count(*) FILTER (WHERE team = 'UNOWNED') FROM os_ev;

\echo '--- ownership coverage per team ---'
SELECT team, count(*) AS bgl_lines FROM bgl_ev GROUP BY team ORDER BY bgl_lines DESC LIMIT 8;
