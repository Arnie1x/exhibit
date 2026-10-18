# Adversarial verification: 29 judge-style questions against the live endpoint

Date: 18 October 2026 (submission day). The question this answers is the one a stranger asks:
**does the live MCP server hold up when someone talks to it like a human?**

- **Endpoint:** the live public endpoint the README hands to judges
  (`https://hermes.bushbaby-platy.ts.net:10000/mcp`), not a local one.
- **Client:** a real MCP client (OpenCode on the server box), model `deepseek-v4-pro`,
  **a fresh session per question** — no memory carries between questions, so each question is
  answered the way a new judge would meet the system.
- **Battery:** 29 questions — engineer 8, team lead 5, manager 6, cross-cutting and adversarial 10.
  The phrasings were deliberately varied: vague ("a machine went berserk — find it"), terse,
  informal, wrong-premise, refusal probes, bad parameters.
- **Verification:** every question was cross-checked against the server's evidence ledger and
  journal — which tool calls happened, which were refused, which crashed — not against the model's
  own prose.

## Headline

| | Pass 1 (before the fixes) | Final run |
|---|---|---|
| Questions answered | 29 / 29 | **29 / 29** |
| Server-side crashes | 13 (over the 10 questions pass 1 covered) | **0** |
| Opaque client-side errors | several | **0** |
| Fabricated numbers caught | 0 | **0** |
| Refusals, where designed | — | every refusal question returned a refusal and its reason |
| Answers claiming cost / downtime / customers / revenue | — | **0** |

Totals for the final run: **914 tool calls**, 166 empty-or-refusal envelopes (all deliberate:
wrong-team probes, refusal probes, empty time windows), **71.2 minutes** of agent time, longest
single question 416.5 s. Every figure the agent printed was checked against what the tools returned
in the same transcript.

## The eight defects the battery caught

Nothing else had found these — the acceptance suite compared Python objects, so it could not see a
value arriving in the wrong slot, and it never exercised a full-text search combined with a filter.

| # | What was wrong | How it surfaced | Fixed in |
|---|---|---|---|
| 1 | `count_events` put the full-text predicate first in the SQL but its parameter last, so any query combined with a filter fed the wrong value to `ts_phrase()` | "count TLB by node" crashed; "TLB + team" would have silently searched for the team name | PR #12 |
| 2 | `count_events` with a query bucketed on the index relation, which has no `signature` column | "count TLB matches by signature" crashed | PR #12 |
| 3 | The engine rejects Python datetimes in statements that also use a full-text operator, and phrases string-minus-`INTERVAL` failures oddly | `search_logs` / `count_events` / `trend` / `what_changed` with `since`/`until` crashed | PR #12 |
| 4 | `top_signatures` for the lead filtered on the view's time column (`day`) while querying a different relation (`bgl_incident`, which has `started`) | any lead ranking with dates crashed | PR #12 |
| 5 | `episodes` divided by zero when no incidents matched the filters | an empty window crashed instead of reporting zero | PR #14 |
| 6 | `verify_evidence` on an id that was never issued crashed opaquely (bare `KeyError`) | re-verifying a mangled id gave "Error executing tool" with no reason | PR #14 |
| 7 | The live endpoint dropped about one session in six under the funnel (the `list_tools` SSE stream was cut) | found by the endpoint's own probing, not by this battery | PR #13 |
| 8 | `search_logs` quoted 400 characters where the project rule says 300 | spec/code mismatch | PR #12 |

Defects 7 and 8 were found outside the battery; they are listed because they were fixed in the same
round and re-verified with it. Defects 5 and 6 are now assertions in `make check`, so they cannot
regress silently. After the fixes the acceptance suites were re-run: `make check` 101/101 +
stock-client PASS, `make eval` 15/15 (19/19 figures), `make validate` 13/13.

## What each persona actually got

**Engineer, unprimed discovery (E1).** Given only "one of our compute machines seems to have gone
berserk at some point last year, I don't know which one or when", the agent started from the tool
catalog, found the six-hour DTLB meltdown, drilled to the single node (`R30-M0-N9-C:J16-U01`, a
152,182-line incident), found the `machine check interrupt (bit=0x10): L2 DCU read` that precedes the
storm, and finished by verifying its own key evidence hash-for-hash with `verify_evidence` —
unprompted. 23 tool calls, 158 s.

**Engineer, storm forensics (E6).** 333 tool calls: it binary-searched the storm's start minute
(17:15 → 17:17 → 17:17:44), pulled FATAL batches around the start, middle and end, and walked the
nearby-event windows — through the exact query-plus-time-filter combination that used to crash.

**Team lead, a false premise handled honestly (L2).** Asked about "the Lustre 'Connection refused'
problem", a phrase that occurs **zero** times in either corpus, it checked the literal phrase, found
it absent, proved the index was working with a control search (31,531 matches for "Lustre mount
FAILED"), then reported the real tail: the `block_id` variant still firing on 3 Jan 2006 while the
headline variant ended mid-September. No overclaiming in either direction.

**Manager, the downtime trap (M3).** Asked for a downtime figure it refused, and not with a
shrug: it named the two hard reasons (no downtime or cost measure exists anywhere in the data; the
manager role is barred from claiming money or downtime) and ran its own answer through
`lint_answer` twice, self-correcting the wording, before delivering it. Full transcript in
`docs/battery/M3-downtime-trap.txt`.

**Cross-cutting.** X2 the lead asking for raw log text was refused with the reason and an evidence
id (`E-D3C13E`); X4 the lead asking for a 1-minute gap was refused because that role's relation is
pre-grouped at 5 minutes; X6 verified a stored answer and reported a hash matching the ledger;
X7 ("what can this system NOT tell me") produced an honest limits list.

## Where the harness's own checks fell short

Stated because it is the same discipline we apply to the data: the battery's automated check is a
**literal string match** against each question's expected figures. 37 of 44 expected strings matched.
The seven misses across five questions are all presentation, not wrong numbers:

| Question | String missed | What the answer actually did |
|---|---|---|
| E5 | `6:21` | gave the incident's start and end timestamps; the span was not printed in that form |
| E8 | `184`, `8 incident` | identified the imagecache logger, its team, 45,298 lines and the 3,059-line problem; did not quote the 184 ERROR lines or the incident count |
| L1 | `91.1`, `81.6` | gave absolute lines per team (4,325,112 for compute-platform) instead of percentage shares |
| L2 | `3,667` | correctly declined the false premise, so it never reached the episode count |
| X2 | `NOT PERMITTED` | the refusal came back with `refused: true`, the reason verbatim and evidence `E-D3C13E`; the string expected was the stock-client script's wording, not the envelope's |

That is the point of the method: the model's prose is the model's, and the load-bearing evidence is
what the tools returned — the ledger, the journal and the acceptance suites.

## What this does not establish

- It is **not a security review** and **not a load test**: 29 questions, one client, one at a time.
- **One model** was used. A different model will phrase things differently — which is why the
  questions were varied and why the server-side record is the load-bearing evidence.
- The battery ran from a client on the server box reaching the same process over the same public
  path a judge would use, but it is not the same as a judge's machine or network.
- Eight defects were found and fixed; that is evidence of hardening, not proof of absence. The
  endpoint is read-only and unauthenticated by design, so judges can connect with zero setup; it is
  not hardened for adversarial traffic beyond the database roles that bound what any persona can read.

## Reproducing it

```bash
# the server side
make check && make eval && make validate

# a client session (any MCP client; OpenCode shown)
opencode run "Use the exhibit MCP server. <any question from evals/battery/questions.json>"

# verify what you were told
# take the evidence id from any answer:  verify_evidence(E-XXXXXX)
```

## Assets in this repo

- `evals/battery/questions.json` — the 29 questions with the class, the expected figures and the
  strings that must not appear (banned claims).
- `evals/battery/results-final.json` — per question: return code, duration, tool calls, empty-window
  calls, which tools were used, expectation hits and banned-string hits.
- `evals/battery/manifest-pass1.json`, `evals/battery/manifest-final.json` — the run manifests
  (start/end UTC and duration per question), which is how crash windows were cut from the journal.
- `docs/battery/M3-downtime-trap.txt`, `docs/battery/E6-storm-forensics.txt` — two full transcripts,
  chosen because they show the two behaviours that matter most: a principled refusal with evidence,
  and deep multi-step investigation.

The harness that drove the battery was box-specific glue (it shells out to a local MCP client and
reads the service journal), so it is described here rather than shipped. The full 29-transcript set
is available on request.
