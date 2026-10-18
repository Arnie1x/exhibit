---
description: A time-boxed way out of a blocker — reproduce, classify, find a tested alternative, decide
argument-hint: <what is failing>
---

Blocker: $ARGUMENTS

1. Reproduce it with the smallest possible command and print the exact error text.
2. Classify it: SereneDB syntax or feature · data or parser · MCP or interface with Arnie's code · environment · our own logic.
3. Investigate by class:
   - SereneDB: check `docs/capabilities.md` and the team plan §16 first (we run 26.09.1.3, which can differ from the docs); then ask the `serenedb-expert` subagent for a tested alternative (`sdb_docs.search`, the docs MCP, a test in `exhibit_scratch`).
   - Data or parser: check `docs/data-notes.md`; sample 20 rows of the failing input; any parser change must keep BGL at 4,747,963 of 4,747,963.
   - Interface: if the fix belongs in Arnie's code (`datasets.py`, the MCP server, the ledger), write the handoff in `docs/process/PROGRESS.md` and work around it on our side.
   - Environment: `docker ps` (SereneDB on 127.0.0.1:7890, image 26.09.1.3), `uv sync`, disk and memory.
4. Look up a prepared fallback: the team plan §11 (cut lines and risk register), `docs/process/build-plan.md` §11 and `docs/capabilities.md`.
5. Offer two options with their time cost, pick the faster one that keeps the current stage's gate safe, and log the decision in `docs/process/PROGRESS.md`.
6. Time box: if it is not solved 20 minutes from now, take the fallback and move on.
