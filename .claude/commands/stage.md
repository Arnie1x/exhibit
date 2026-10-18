---
description: Run Adnan's part of one team-plan stage — plan, build, gate checks, commit, docs/process/PROGRESS.md
argument-hint: <team stage number> [auto] [fix: <what failed>]
disable-model-invocation: true
---

Arguments: $ARGUMENTS

The first token is the team stage number N (team plan `docs/process/PLAN.md` §11). `auto` means do not stop for my approval. `fix: …` means repair only that failure.

1. **Load context.** CLAUDE.md is already loaded. Read `docs/process/PROGRESS.md`; in the team `docs/process/PLAN.md`, the §11 row for stage N (window and gate), §12 (split and interface contract) and §16 (agent rules); in `docs/process/build-plan.md`, the Section 0 stage map and every section it lists for stage N; and `docs/capabilities.md` and `docs/data-notes.md`.
2. **Clock.** Run `date` and compare with the stage's window in §11. Print `Stage N · window <start>–<end> · on time | behind by <x> h`. If behind by more than an hour, recommend cuts from the team plan's §11 cut lines.
3. **Scope.** Do only Adnan's part of stage N (CLAUDE.md, "Adnan's lane"). Anything that needs Arnie's code goes into `docs/process/PROGRESS.md` under "Handoffs to Arnie". Where `docs/process/build-plan.md` names files, targets or tools that differ from the repo and the team plan, follow the repo and never create a parallel file (for example, no `sql/40_episodes.sql` when episodes live in `sql/30_views.sql`).
4. **Fix mode.** If the arguments contain `fix:`, reproduce that failure, fix it, re-run the failed check and `make bootstrap smoke`, then go to step 8.
5. **Plan.** Turn the work into a task list (your session's task or todo tool) with an estimate per task, adapted to what the repo, `docs/process/PROGRESS.md` and `docs/capabilities.md` say is true now. Unless `auto` was given or the plan was already approved in plan mode, wait for my go-ahead.
6. **Build.** Follow CLAUDE.md. Ask the `serenedb-expert` subagent before writing unfamiliar SereneDB SQL; have the `sql-verifier` subagent confirm every number that goes into a test, doc, slide or answer. Change scripts, never live state, and rebuild with `make bootstrap`. Start long jobs in the background and note them in `docs/process/PROGRESS.md`. Commit after each working step.
7. **Gate.** Run the §11 gate for stage N literally, plus any acceptance item from `docs/process/build-plan.md` that applies to your part. Print a table: check · command or proof · result · PASS/FAIL.
8. **Close.**
   - All PASS: `make bootstrap smoke` green → conventional commit (`feat(views): …`, `fix(data): …`) → push → update `docs/process/PROGRESS.md` (stage log, requirements tracker, done, decisions, measured numbers with their commands, handoffs, open issues, next).
   - Any FAIL: commit as work in progress (`wip(stage-N): …`), put each failure under "Open issues" and stop.
9. **Report** in at most five lines: what works now, the numbers measured, what failed or was cut, handoffs for Arnie, and the exact next command.
