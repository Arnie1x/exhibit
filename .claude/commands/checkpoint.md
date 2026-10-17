---
description: Commit the working state, update PROGRESS.md and print the requirements tracker
argument-hint: [short summary]
disable-model-invocation: true
---

Checkpoint: $ARGUMENTS

1. Run `make bootstrap smoke` and the tests (`make test`, or `uv run pytest -q` if there is no such target), then `uv run ruff check --fix` and `uv run ruff format` on changed Python files. If anything fails, the commit is work in progress (`wip(…): …`) and the failure goes under "Open issues".
2. Run `git status` and make sure nothing staged is `.env`, a credential, raw data, Parquet output or a file over 5 MB.
3. Commit with a conventional message (`feat(views): …`, `fix(data): …`, `docs: …`; use the arguments as the summary if given) and push.
4. Update `PROGRESS.md`: done, decisions, measured numbers (value plus the command that produced it), background jobs, handoffs to Arnie, open issues, next; tick the requirements tracker with a proof path for each ticked row.
5. Print the time against the current stage's window in the team plan §11, the requirements tracker, any handoffs to Arnie, and the single most valuable next step.
