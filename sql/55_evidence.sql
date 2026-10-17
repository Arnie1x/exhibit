-- 55_evidence.sql -- the evidence ledger.
--
-- Every answer the server produces cites an evidence id (`E-AB12CD`). This table is where those
-- ids live: the SQL that produced the number, the parameters bound into it, and a hash of the rows
-- that came back. `verify_evidence` re-runs the stored SQL and compares -- so a judge can check a
-- number instead of trusting it, which is the whole point of the project.
--
-- Append-only on purpose: re-running the same question adds a row rather than overwriting, so the
-- history of an answer stays visible.
--
-- This file is deliberately NOT part of sql/50_roles.sql. That file is Adnan's lane; grants here
-- belong in one table per statement anyway, which the engine requires.

CREATE TABLE IF NOT EXISTS exhibit_evidence (
    evidence_id  VARCHAR NOT NULL,   -- stable id of query+params, computed by the server
    created_at   TIMESTAMP NOT NULL,
    tool         VARCHAR NOT NULL,
    persona      VARCHAR NOT NULL,   -- who asked
    role         VARCHAR NOT NULL,   -- the database role it ran under
    dataset      VARCHAR NOT NULL,
    scope        VARCHAR NOT NULL,   -- JSON: the filters and parameters of the question
    sql_text     VARCHAR NOT NULL,   -- the statement, with %s placeholders
    params_json  VARCHAR NOT NULL,   -- JSON, type-tagged so a re-run binds the same types
    rows_hash    VARCHAR NOT NULL,   -- sha1 of the rows that came back
    row_count    INTEGER NOT NULL
);

GRANT SELECT ON exhibit_evidence TO exhibit_engineer;
GRANT INSERT ON exhibit_evidence TO exhibit_engineer;
GRANT SELECT ON exhibit_evidence TO exhibit_lead;
GRANT INSERT ON exhibit_evidence TO exhibit_lead;
GRANT SELECT ON exhibit_evidence TO exhibit_manager;
GRANT INSERT ON exhibit_evidence TO exhibit_manager;
