# KICKOFF — joining the team build

The team plan (`PLAN.md`, Arnie, Sat 10:30) runs the build, and Stages 0–1 are already done: the repo parses, derives, indexes and measures. This kit adds coding-agent rules, commands and subagents for Adnan's lane (data, views, roles SQL, verification, bench, ground truth).

## Install the kit (about 5 minutes)

- [ ] `git pull` the team repo.
- [ ] Unzip `exhibit-kit.zip` into a temporary folder and copy it in without overwriting anything: `rsync -a --ignore-existing <kit-folder>/ <repo>/`.
- [ ] If the repo already had `CLAUDE.md`, `.mcp.json`, `.gitignore` or `.claude/settings.json`, merge ours into them by hand (append our `CLAUDE.md` under its own heading). Never replace the team's `PLAN.md`.
- [ ] `/mcp` shows `serenedb-docs` connected.
- [ ] SereneDB runs from the pinned image: `docker run -d --name serenedb -p 127.0.0.1:7890:7890 -v serenedb-data:/var/lib/serenedb -v "$PWD/data":/data serenedb/serenedb:26.09.1.3`. Or use the team box over Tailscale (address in `PLAN.md` §3).
- [ ] `make bootstrap smoke` prints 4,747,963 / 207,812 and 348,460 → 19,250.
- [ ] Star SereneDB on GitHub (a listed prerequisite).
- [ ] Commit: `chore: add the coding-agent kit for the data lane`.

## Clock (team plan §11)

| When | Team stage | Adnan's part |
| --- | --- | --- |
| Sat now–12:00 | 0–1 Probe, data layer (done) | Re-check and verify (first prompt below) |
| Sat 12:00–14:00 | 2 MCP skeleton (Arnie) | Golden SQL for `describe_data`, `search_logs`, `count_events`; views Arnie asks for |
| Sat 14:00–17:00 | 3 W1/W2 tools | Views behind `top_signatures`, `trend`, `episodes`, `durations`, `ownership`; `make demo` numbers match team plan §9 |
| Sat 17:00–18:00 | Q&A prep | The questions in team plan §13; explain W1 in 90 seconds |
| Sat 18:00–20:00 | Q&A slot (10 min) | Write the answers into `PLAN.md` the same night |
| Sat 20:00–24:00 | 4 Roles, contract, lints | `sql/50_roles.sql` views and grants; manager view without log text |
| Sun 00:00–08:00 | Sleep | OTel slice bench running in the background |
| Sun 08:00–12:00 | 5 Validation, eval | Ground-truth validation script the agent cannot reach |
| Sun 12:00–15:00 | 6 README, clean-check, slides | README sections on data, loader, ownership and limitations |
| Sun 15:00–19:00 | 7 Video (5 min and a 3-min cut) | Real queries, real numbers on screen |
| Sun 19:00–22:00 | 8 Submission | Checklist in team plan §15; repo public |
| Sun 22:00–23:59 | Buffer | — |

## First prompt (paste now)

```text
Read CLAUDE.md, then the team plan PLAN.md in full (§11, §12 and §16 closely), docs/capabilities.md, docs/data-notes.md and docs/build-plan.md Section 0. Do not scaffold or rebuild anything that exists: the data layer is done, and the team plan wins wherever documents disagree.

Then work through my two-hour list from PLAN.md §12, in order, one conventional commit each:
1. Run `make probe` and try to break docs/capabilities.md: re-measure the partial-index row and the dictionary row, and record the exact statements and results.
2. Independently confirm 348,460 → 19,250 (5-minute episodes per signature × midplane) and the 136,209 lines on one node on 2005-06-11, through the sql-verifier subagent with freshly written SQL.
3. Port sql/50_roles.sql to bgl_ev and os_ev (it still references the old flat tables): engineer, lead and manager views with their GRANTs; the manager view has no log text but keeps component and team.
4. Extend os_sig with what W2 needs: lifecycle durations, the imagecache traceback grouping, the CRITICAL auth lines.
After each item print an acceptance table, update PROGRESS.md, and leave Arnie a handoff note there if his code is affected. Finish by telling me the next command.
```

## After that

```text
/clear
/stage 3                        # team stage numbers; Shift+Tab into plan mode first to approve the task list
/stage 3 fix: <what failed>     # when a gate check fails
/stage 5 auto                   # no approval stop (start the agent in its accept-edits permission mode for unattended runs)
/checkpoint <summary>           # commit + PROGRESS.md + requirements tracker
/verify <file or folder>        # re-derive every number with independent SQL
/judge                          # after Stage 3, after Stage 5, before submission
/unstuck <what is failing>      # after 20 minutes on one problem
```

## Before you sleep (Sun 00:00)

```text
Start the huge-data bench from docs/build-plan.md §9c steps 1–2 in the background with nohup, logging to logs/: the one-file metadata count and a one-minute slice over the remote OTel Parquet. Record the machine's CPU, RAM and disk. Put the PIDs and log paths in PROGRESS.md under "Background jobs".
```

## After you wake (Sun 08:00)

```text
Check the background jobs listed in PROGRESS.md. Record results under "Measured numbers" with the command behind each, commit, and tell me if anything blocks Stage 5.
```
