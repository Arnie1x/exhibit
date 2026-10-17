-- Golden figures for the eval bank, hand-written against the derived relations.
--
-- Deliberately NOT the SQL the tools build: each statement here is fixed and returns exactly the
-- figure a question is scored against, so a change to a tool's SQL cannot silently move a number.
-- The figures themselves were first recomputed from the raw corpus without the views
-- (tests/golden/stage3_numbers.sql: 76 of 76 checks matched; scripts/validate_ground_truth.py
-- adds 13 expectations against the answer keys) and are pinned in sql/99_smoke.sql.
-- Convention: `-- name: <id>` above a statement returning ONE row ONE column.
--
-- Run through `make eval` (evals/run_eval.py). Every row must reproduce on a fresh bootstrap.

-- name: q01-burst-incidents
-- the collapse of 348,460 alert lines at a five-minute gap
SELECT count(*)::bigint FROM bgl_incident;

-- name: q02-burst-lines
-- the deepest incident's own line count
SELECT lines::bigint FROM bgl_incident ORDER BY lines DESC LIMIT 1;

-- name: q02b-burst-nodes
SELECT nodes::bigint FROM bgl_incident ORDER BY lines DESC LIMIT 1;

-- name: q03-search-total
-- the phrase, as the engineer's role searches it
SELECT count(*)::bigint FROM bgl_idx WHERE content @@ ts_phrase('data TLB error interrupt');

-- name: q04-gap-1
SELECT sum(episodes_1min)::bigint FROM bgl_episode_sensitivity;

-- name: q04b-gap-60
SELECT sum(episodes_60min)::bigint FROM bgl_episode_sensitivity;

-- name: q05-dtlb-episodes
SELECT episodes_5min::bigint FROM bgl_episode_sensitivity
WHERE signature = 'data TLB error interrupt';

-- name: q06-lead-top-lines
SELECT alert_lines::bigint FROM bgl_signature_stats ORDER BY alert_lines DESC LIMIT 1;

-- name: q07-lead-top-episodes
SELECT max(episodes_5min)::bigint FROM bgl_signature_stats;

-- name: q08-last-day-lines
SELECT sum(lines)::bigint FROM lead_bgl_daily WHERE day = DATE '2006-01-04';

-- name: q09-manager-peak-blast
SELECT max(nodes_affected)::bigint FROM mgr_bgl_risk;

-- name: q10-manager-top-episodes
SELECT max(episodes_5min)::bigint FROM mgr_bgl_risk;

-- name: q11-manager-alert-lines
SELECT sum(alert_lines)::bigint FROM mgr_bgl_risk;

-- name: q12-ownership-rows
SELECT count(*)::bigint FROM owner_map;

-- name: q13-raw-burst-node
-- the burst recomputed from the raw derived table, with no tool and no view: one machine, one day
SELECT count(DISTINCT node)::bigint FROM bgl_ev
WHERE is_alert AND ts >= TIMESTAMP '2005-06-11' AND ts < TIMESTAMP '2005-06-12';
