-- sql/20_indexes.sql
-- Dictionary + inverted indexes. Search targets these RELATIONS BY NAME (pattern B).
--
-- Two facts measured on 26.09.1.3 that shape this file:
--   1. The documented dictionary syntax is the parenthesised form with template=,
--      NOT `CREATE TEXT SEARCH DICTIONARY x AS split_text(...)` -- that is a syntax error.
--   2. `@@` must run against an indexed relation. Query bgl_idx / os_idx, not bgl_ev / os_ev.
--
-- Run: psql -h 127.0.0.1 -p 7890 -U postgres -f sql/20_indexes.sql

\set ON_ERROR_STOP on
\timing on

DROP TEXT SEARCH DICTIONARY IF EXISTS log_text;
CREATE TEXT SEARCH DICTIONARY log_text (
    template   = 'text',
    locale     = 'en_US.UTF-8',
    case        = 'lower',
    stemming    = false,
    accent      = false,
    frequency   = true,
    position    = true
);

-- Verify the dictionary splits node IDs and prefixed tokens the way we expect.
SELECT ts_lexize('log_text', 'R02-M1-N0-C:J12-U11 ciod: failed to read message prefix') AS tokens;

DROP INDEX IF EXISTS bgl_idx;
CREATE INDEX bgl_idx ON bgl_ev
    USING inverted (id, content log_text, ts, level_rank, alert_category, component, level,
                    node, node_kind, rack, midplane, nodecard, team, template_id, is_alert)
    WITH (optimize_top_k = 'bm25(1.2, 0.75)');

DROP INDEX IF EXISTS os_idx;
CREATE INDEX os_idx ON os_ev
    USING inverted (id, content log_text, ts, level, service, logger, team, instance_id,
                    req_id, tenant_id, endpoint, http_method, status)
    WITH (optimize_top_k = 'bm25(1.2, 0.75)');

-- Indexes are eventually consistent; refresh after a load.
VACUUM (REFRESH_TABLE) bgl_ev;
VACUUM (REFRESH_TABLE) os_ev;

\echo '--- index smoke test (search must target the index relation) ---'
SELECT count(*) AS bgl_phrase_hits FROM bgl_idx WHERE content @@ ts_phrase('data TLB error interrupt');
SELECT count(*) AS os_term_hits    FROM os_idx  WHERE content @@ 'base';
