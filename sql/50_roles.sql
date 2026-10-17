-- Three role views over the OTel log corpus  (National AI Hackathon 2026, SereneDB logs track).
-- Everything here is COMPUTED BY THE DATABASE. The agent's job is to explain these rows and
-- recommend next steps -- never to produce a number a query could have produced.
--
--   psql -h 127.0.0.1 -p 7890 -U postgres -P pager=off -f /home/ubuntu/serenedb/roles.sql
--
-- All timings below are from the 10M-row load on the lab box (2 vCPU, arm64).

\pset border 2
\timing on

-- =====================================================================================
-- 0. DATA RECON -- run this FIRST on any corpus you are handed.
--    Three facts here changed the design of every query below.
-- =====================================================================================
\echo '### 0. RECON — span, volume, trace-id coverage'
SELECT min(Timestamp)                                        AS first_log,
       max(Timestamp)                                        AS last_log,
       count(*)                                              AS rows_total,
       count(DISTINCT NULLIF(ServiceName, ''))                AS services_named,
       sum(CASE WHEN TraceId = '' THEN 1 ELSE 0 END)          AS rows_without_traceid,
       count(DISTINCT NULLIF(TraceId, ''))                    AS distinct_traces
FROM otel_logs_idx;

\echo '### 0b. RECON — the severity vocabulary is NOT clean (note "info" vs "information")'
SELECT SeverityText, count(*) AS n FROM otel_logs_idx GROUP BY SeverityText ORDER BY n DESC LIMIT 12;

-- =====================================================================================
-- ROLE 1 — ENGINEER: "an order confirmation is failing, show me the evidence"
-- =====================================================================================
\echo '### ENGINEER 1a — the exact failure, newest first (phrase search + time ordering)'
SELECT Timestamp, ServiceName, SeverityText, left(Body, 66) AS body
FROM otel_logs_idx
WHERE Body @@ ts_phrase('failed', 'to', 'send', 'order', 'confirmation')
ORDER BY Timestamp DESC
LIMIT 6;

\echo '### ENGINEER 1b — same corpus, ranked by RELEVANCE (BM25) instead of time'
SELECT ServiceName, left(Body, 58) AS body,
       ROUND(BM25(otel_logs_idx.tableoid)::numeric, 3) AS bm25
FROM otel_logs_idx
WHERE Body @@ ts_any(['timeout', 'refused', 'exception', 'failed'])
ORDER BY BM25(otel_logs_idx.tableoid) DESC
LIMIT 6;

\echo '### ENGINEER 1c — correlation: what ELSE happened in the failing traces'
WITH hit AS (
  SELECT DISTINCT TraceId FROM otel_logs_idx
  WHERE ServiceName = 'frontend' AND Body @@ ts_phrase('failed', 'to', 'place', 'order') AND TraceId <> ''
)
SELECT a.ServiceName, a.SeverityText, count(*) AS lines
FROM otel_logs_idx a
WHERE a.TraceId <> '' AND EXISTS (SELECT 1 FROM hit b WHERE b.TraceId = a.TraceId)
GROUP BY a.ServiceName, a.SeverityText
ORDER BY lines DESC
LIMIT 10;

-- =====================================================================================
-- ROLE 2 — TEAM LEAD: "which problems keep coming back?"
-- =====================================================================================
\echo '### TEAM LEAD 2a — recurring failures by service and severity, with real trace impact'
-- NULLIF(TraceId,'') matters: empty trace ids otherwise collapse into ONE distinct value and
-- every row reports "1 affected trace". This corpus has 9,999,000+ rows like that.
SELECT ServiceName,
       SeverityText,
       count(*)                                AS occurrences,
       count(DISTINCT NULLIF(TraceId, ''))     AS affected_traces,
       min(Timestamp)                          AS first_seen,
       max(Timestamp)                          AS last_seen
FROM otel_logs_idx
WHERE TraceId <> '' AND Body @@ ts_any(['failed', 'error', 'exception', 'refused', 'timeout', 'denied'])
GROUP BY ServiceName, SeverityText
ORDER BY occurrences DESC
LIMIT 10;

\echo '### TEAM LEAD 2b — per-second trend (this corpus spans ~17 seconds, not days)'
-- NOTE: Timestamp is a nanosecond type; date_trunc needs an explicit cast. Without it:
--   ERROR: No function matches ... 'date_trunc(STRING_LITERAL, TIMESTAMPTZ_NS)'
SELECT date_trunc('second', Timestamp::timestamptz)     AS second_bucket,
       count(*)                                         AS failures,
       count(DISTINCT NULLIF(TraceId, ''))              AS traces
FROM otel_logs_idx
WHERE Body @@ ts_any(['failed', 'error', 'exception', 'refused', 'timeout'])
GROUP BY 1
ORDER BY 1
LIMIT 20;

-- =====================================================================================
-- ROLE 3 — MANAGER: "what do we prioritise?"
-- =====================================================================================
\echo '### MANAGER 3a — services ranked by distinct affected traces (impact, not line count)'
SELECT ServiceName,
       count(DISTINCT NULLIF(TraceId, '')) AS affected_traces,
       count(*)                            AS log_lines
FROM otel_logs_idx
WHERE TraceId <> '' AND Body @@ ts_any(['failed', 'error', 'exception', 'refused', 'timeout'])
GROUP BY ServiceName
ORDER BY affected_traces DESC
LIMIT 10;

\echo '### MANAGER 3b — blast radius: how many distinct services each failing trace touches'
SELECT services_touched, count(*) AS traces_in_bucket
FROM (
  SELECT TraceId, count(DISTINCT ServiceName) AS services_touched
  FROM otel_logs_idx
  WHERE TraceId <> '' AND Body @@ ts_any(['failed', 'error', 'exception', 'refused', 'timeout'])
  GROUP BY TraceId
) t
GROUP BY services_touched
ORDER BY services_touched;

\echo '### MANAGER 3c — the one-line verdict the agent may phrase, never compute'
SELECT count(DISTINCT NULLIF(TraceId, ''))  AS traces_affected,
       count(DISTINCT NULLIF(ServiceName, '')) AS services_involved,
       min(Timestamp)                       AS incident_start,
       max(Timestamp)                       AS incident_end
FROM otel_logs_idx
WHERE TraceId <> '' AND Body @@ ts_any(['failed', 'error', 'exception', 'refused', 'timeout']);
