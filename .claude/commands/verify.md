---
description: Re-derive every number in an answer, investigation, doc or slide with independent SQL and report match or mismatch
argument-hint: <path to a Markdown file or folder> | plan | last
---

Target: $ARGUMENTS (`plan` means the numbers in the team `PLAN.md`; `last` means the newest folder under `investigations/`)

Delegate to the `sql-verifier` subagent with this brief:

- Extract every numeric claim in the target (counts, shares, rates, percentiles, durations, lifts, rankings, dates) together with the evidence ID or query it cites, if any.
- Layer 1, reproducibility: re-run each cited query (or the `verify_evidence` tool for evidence IDs) and confirm the number appears in `make smoke` or `make demo` output where the plan says it does.
- Layer 2, correctness: write new SQL from the claim's wording, different from the stored query. Full-text claims keep the same operator (`@@` against the index relation by name); aggregates, episodes and durations query the derived tables directly. Never confirm a count with `LIKE`.
- Write `<target folder>/VERIFY.md` (for `plan`: `docs/verify-plan.md`) with one row per claim: claim · where it appears · evidence · stated value · independent value · independent SQL · operator · verdict (match, mismatch or unverifiable).
- Do not edit source code or the target; write only that file.

Then, in this session, print the verdict counts. For each mismatch, find the cause (operator, sentinel or NULL handling, VARCHAR timestamp cast, episode gap or scope, parser losses, stale state) and propose the fix. A number with no query behind it counts as a mismatch.
