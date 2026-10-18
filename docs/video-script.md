# Video script: what to show, what to say, what you should see

Team **Logging off Early** · SchubKI National AI Hackathon 2026, track 04 · **5:00 maximum**, plus a
**3:00 cut** built from the same takes (`docs/process/PLAN.md` §15).

**Read only the SAY lines out loud.** Everything else is for you, not the microphone. Numbers in SAY
are spoken exactly as written — "152,183" is seven words.

Where this script and `docs/process/build-plan.md` disagree, the repo wins: the repo is what runs.

---

## Pre-flight — five things to check before you hit record

1. **Everything green.** `make bootstrap`, then `make smoke`, `make demo`, `make check`, `make eval`,
   `make validate`. All pass, and the output matches the CONFIRM line in each unit. On Windows there
   is no `make`: run each recipe by hand as the README says (`MSYS_NO_PATHCONV=1`, `PYTHONUTF8=1`).
2. **Two clients connected, each listing 12 tools.** One local, through the repo's `.mcp.json`
   (`exhibit`, stdio), one on the live endpoint (`exhibit-demo`, streamable HTTP). Record the local
   one; show the live one in U3.
3. **Record the fallbacks first.** Capture the full `make demo` output and the full output of
   `uv run python scripts/stage2_mcp_client.py` as separate clips. Every number the client shows on
   camera is also printed by one of those two. If a live take goes sideways, cut to the fallback and
   the narration does not change.
4. **Screen dressing.** Terminal at 18 pt or larger, at least 120 columns (the `make demo` tables are
   wide), commands typed ahead of time so nothing is composed live. Nothing on screen may show `.env`
   or any IP other than `127.0.0.1`; the only hostname allowed is the public demo endpoint, which the
   README already publishes.
5. **One take per unit.** That is what makes the 3:00 cut an edit rather than a second recording
   session. Deck: **"Exhibit: SQL computes, the LLM explains"**, 17 slides, `docs/slides.pdf`. Slide
   numbers below all refer to it.

---

## The run of show

| Unit | What it is | 5:00 | 3:00 |
| --- | --- | --- | --- |
| U1 | Open | 0:00–0:16 | 0:00–0:16 |
| U2 | Lines are not incidents — **the live query** | 0:16–0:47 | 0:16–0:46 |
| U3 | How it works, how to connect | 0:47–1:04 | cut |
| U4 | Roles in the database | 1:04–1:23 | cut |
| U5 | W1, the engineer | 1:23–1:45 | 0:46–1:07 |
| U6 | The gap is a parameter | 1:45–1:56 | cut |
| U7 | W1, the team lead | 1:56–2:26 | 1:07–1:37 |
| U8 | W1, the manager | 2:26–2:54 | 1:37–2:05 |
| U9 | W2, OpenStack | 2:54–3:23 | cut |
| U10 | Ground truth, kept out of the agent | 3:23–3:55 | 2:05–2:37 |
| U11a | Re-run any number | 3:55–4:04 | 2:37–2:46 |
| U11b | The lint and the eval | 4:04–4:15 | cut |
| U12 | A billion rows | 4:15–4:37 | cut |
| U13a | The data wins | 4:37–4:44 | cut |
| U13b | Close | 4:44–4:54 | 2:46–2:56 |
| — | End card, silent | 4:54–5:00 | 2:56–3:00 |

**The 3:00 cut is these eight units, in this order, word for word:** U1, U2, U5, U7, U8, U10, U11a,
U13b. Same takes, less screen time around each, and no unit in it depends on a cut one. Slide 4
("One corpus, three rankings") is the summary card for U5–U8 and is not narrated on its own.

---

## U1 · Open · 16 s
**5:00** 0:00–0:16 · **3:00** 0:00–0:16

- **SHOW** — slide 1 (cover), then slide 2 ("One question, three readers") from "for the engineer".
- **SAY** — Exhibit answers one question three ways: for the engineer who fixes it, the lead who
  staffs it, and the manager who decides. SQL computes, the LLM explains: every number on screen
  comes from a query you can re-run.
- **DEMONSTRATES** — the whole product in two sentences: one question, three readers, and everything
  on screen is checkable.
- **CONFIRM** — nothing numeric. Slide 1 shows `$ exhibit-mcp`, `connected: exhibit 0.3.0`, `12 tools`.

---

## U2 · Lines are not incidents — the live query · 31 s
**5:00** 0:16–0:47 · **3:00** 0:16–0:46

- **SHOW** — terminal. Type `make smoke` and let it run. Hold on **section 4b** (the one-node versus
  fleet comparison), then section 2. Box each figure as it is spoken. Slide 3 closes the unit as a
  two-second card. This is the "real query, real number on screen" moment the brief asks for.
- **SAY** — Live, on SereneDB. One node wrote 152,183 alert lines in one evening: 44 percent of all
  alerts. Days later, one event hit 22,529 nodes with only 49,154 lines. Lines point at the wrong
  one. So we count incidents: at a five-minute gap, 348,460 alert lines become 19,250.
- **DEMONSTRATES** — the project's whole thesis: ranking by volume puts the wrong problem first, and
  you can watch that happen live rather than be told about it.
- **CONFIRM** — 152,183 lines on 1 node (2005-06-11 17:17 → 23:39) · 49,154 lines across 22,529 nodes
  (2005-06-14) · 348,460 alert lines → 19,250 incidents at a 5-minute gap.

---

## U3 · How it works, and how to connect · 17 s
**5:00** 0:47–1:04 · **3:00** cut

- **SHOW** — slide 5 (architecture) → slide 6 (the twelve tools) → the **local** client's tool list →
  slide 7 ("Three ways to connect") → a second client window on the **live** endpoint showing the
  same tool list.
- **SAY** — Under the hood: an MCP server with twelve tools. SereneDB searches and counts; every tool
  returns its query and an evidence ID. Clone the repo and the server is registered, or point any
  client at our live endpoint.
- **DEMONSTRATES** — a judge does not have to build anything to try it: there is a public endpoint,
  and the same server runs from the repo.
- **CONFIRM** — 12 tools listed by name (`describe_data` … `lint_answer`). Slide 7 carries the
  endpoint URL and "Tested 18 Oct".

---

## U4 · Roles in the database · 19 s
**5:00** 1:04–1:23 · **3:00** cut

- **SHOW** — slide 8 for two seconds, then the MCP client.
- **TYPE** — `Count BGL lines grouped by team three times: as persona engineer, as lead, as manager. Then, as the lead, search BGL for "ciod".`
- **SAY** — Roles live in the database, not in the prompt. One call, three personas: the engineer
  counts every row, the lead gets lines already summed by team, and the manager sees only alert
  lines. Ask for log text as the lead, and SereneDB refuses.
- **DEMONSTRATES** — the differentiator: scope enforced by database roles and grants, so a lead
  cannot read a log line. Not an instruction in a prompt, a permission in the engine.
- **CONFIRM** — engineer `4,747,963 matching rows` · lead `4,747,963 sum of lines` · manager
  `348,460 sum of alert_lines` · the lead's search returns `NOT PERMITTED for lead@exhibit_lead`. One
  question, three numbers, all three correct for what that role can see.

---

## U5 · W1, the engineer · 22 s
**5:00** 1:23–1:45 · **3:00** 0:46–1:07

- **SHOW** — slide 9, then the MCP client. You can overlay the `make demo` W1 E1 row for DTLB; it
  carries `top_node_pct`.
- **TYPE** — `Persona engineer. Which BGL problem should we fix first? Search the phrase "data TLB error interrupt", count its episodes at a 5-minute gap, then show the deepest episode in the corpus.`
- **SAY** — Question one: what do we fix first? The engineer searches the loudest signature, data TLB
  error interrupt: 152,734 lines. Episodes make that 117 incidents, and 99.64 percent of the lines
  come from one node. One machine, not the fleet.
- **DEMONSTRATES** — the engineer's job done properly: phrase search, then incidents rather than
  lines, then blast radius — which is what turns a "huge" problem into one sick machine.
- **CONFIRM** — `152,734` matches as `phrase (ts_phrase)` · `117` incidents at 5 minutes · `99.64%`
  from one node · the deepest incident is on `R30-M0`: 152,182 lines, 1 node, 6:21:47.98. Evidence id
  `E-55EF08`, stable on every run, local and live — **shown, not read aloud**.

---

## U6 · The gap is a parameter · 11 s
**5:00** 1:45–1:56 · **3:00** cut

- **SHOW** — slide 9, the gap box bottom-right — or terminal `make demo` W1 E4.
- **SAY** — The count depends on the gap: 132, 117 or 57 incidents at one, five or sixty minutes. So
  every answer states its gap.
- **DEMONSTRATES** — honesty about a hidden parameter. Most teams would report one number and never
  mention what it depends on.
- **CONFIRM** — 132 / 117 / 57, per signature × midplane.

---

## U7 · W1, the team lead · 30 s
**5:00** 1:56–2:26 · **3:00** 1:07–1:37

- **SHOW** — the MCP client for the ranking, then slide 10 (team shares and the weekly chart).
  `make demo` W1 L3 (team shares), L4 (weekly trend) and L4b (the chart's bars) are the fallback.
- **TYPE** — `Persona lead. Rank BGL signatures by episodes at a 5-minute gap, top 2, with the owning team.`
- **SAY** — The lead gets no raw lines: signatures by owning team, from our fictional ownership map.
  Compute-platform owns 91.1 percent of lines but 51.7 percent of incidents. By incidents, two
  signatures lead: Lustre mount failures, 3,667, and a ciod socket error, 3,638. The weekly chart
  splits them: Lustre stopped after three weeks; every ciod incident falls in the last nine.
- **DEMONSTRATES** — the lead needs a different unit of work: not "what broke" but "whose work is
  this, and is it getting better or worse". Two problems of similar size, opposite trajectories.
- **CONFIRM** — Lustre 3,667 and ciod 3,638 incidents, at most 8 nodes in one incident · teams
  `compute-platform` and `workload-runtime` · compute-platform 91.09% of lines and 51.7% of
  incidents, workload-runtime 48% of incidents · Lustre 3 active weeks (1,872 / 1,244 / 551) and
  **0** in the last nine; ciod all 3,638 in the last nine.
- **NOTE** — the weekly chart comes from `make demo` L4/L4b, not from the `trend` tool: the lead's
  view is daily, and `trend(bucket="week")` as the lead correctly returns NOT PERMITTED.

---

## U8 · W1, the manager · 28 s
**5:00** 2:26–2:54 · **3:00** 1:37–2:05

- **SHOW** — slide 11, then terminal `make demo` W1 M1, M2, and the closing "Not established" line —
  it runs under the manager role, which has no log text and no node IDs. Slide 4 is the summary card.
- **SAY** — The manager sees no log text and no node IDs, only risks ranked by blast radius and
  persistence. First: the rts panic, owned by compute-platform, on 3,394 nodes across 124 days. The
  data TLB error, first by lines, is twelfth. A slow burn across the fleet outranks a fire on one
  machine. What the logs cannot measure is marked not established.
- **DEMONSTRATES** — the manager's ranking is deliberately unlike the engineer's, and the same corpus
  supports both because the criteria are stated. Plus the refusal to invent impact.
- **CONFIRM** — risk position 1 is `KERNRTSP`, KERNEL, compute-platform, 3,394 nodes, 124 active days ·
  DTLB is lines-position 1 and risk-position 12 (541 nodes, 11 active days) · the closing line reads
  "Not established by the logs: cost, downtime, impact on jobs or users, root cause." — **shown, not
  read aloud**.

---

## U9 · W2, OpenStack · 29 s
**5:00** 2:54–3:23 · **3:00** cut

- **SHOW** — slide 12, then terminal `make demo` W2 M1 (problems), E1 (latency) and L1 (spawn
  ranking). The ranking can also come from the client:
  `durations(dataset="openstack", persona="lead", by="spawn_s", limit=4)`.
- **SAY** — On OpenStack: were the instances meant to be slow actually slow? The 188 error and
  critical lines are 8 tracebacks of one image-cache bug, plus 2 token-validation incidents. Latency
  cannot see the anomaly: 0.2340 against 0.2341 seconds. Lifecycle duration can: the four slowest
  spawns run 50.72 down to 29.46 seconds.
- **DEMONSTRATES** — a second corpus and a second kind of anomaly. Log levels and API latency both
  miss it; only lifecycle duration exposes it, and it is believable because it is measured against a
  median.
- **CONFIRM** — 188 ERROR + CRITICAL lines (186 + 2) · 184 of them are 8 `InvalidDiskInfo` tracebacks,
  8 incidents, platform-services; the other 4 are 2 token-validation incidents, identity, and they are
  the only 2 CRITICAL lines · mean latency 0.234 s abnormal vs 0.2341 s normal · spawns 50.72 / 41.81
  / 31.27 / 29.46 s at positions 1–4, 26.69 s at 5, median 19.74 s.

---

## U10 · Ground truth, kept out of the agent's reach · 32 s
**5:00** 3:23–3:55 · **3:00** 2:05–2:37

- **SHOW** — terminal, `make validate`. Hold on section 0 (the two PASS lines), then section 1
  (positions 1–4), then section 2 (agreement). Slide 14 is the summary card.
- **SAY** — Both corpora ship with answer keys. OpenStack's never reaches the agent: no tool reads it,
  no table holds it; a separate script scores us. The lead's duration ranking puts its four labelled
  instances at positions 1 to 4 of 2,069: about 1 in 761 billion by chance. BGL's label is part of
  the data, so there we test agreement: text-only signatures match it on 99.9998 percent of lines.
- **DEMONSTRATES** — the strongest credibility move in the submission: the agent never sees the
  answers, an outside script scores the result, and the result is 1–4 of 2,069.
- **CONFIRM** — `make validate` → 13/13 · no tool reads labels; 0 relations and 0 columns hold
  `anomaly_labels.txt` · positions [1, 2, 3, 4] of 2,069 · chance 1 in 761,325,852,001 · 99.9998%
  agreement over 4,747,963 lines.

---

## U11a · Re-run any number · 9 s
**5:00** 3:55–4:04 · **3:00** 2:37–2:46

- **SHOW** — slide 13, then the MCP client.
- **TYPE** — `Verify evidence E-55EF08.`
- **SAY** — Any number can be checked: verify evidence re-runs the stored query. Match, and the live
  server gives the same ID.
- **DEMONSTRATES** — "trust us" is not the offer; "run it yourself" is. The ledger stores the SQL, the
  role and a result hash for every answer, including the refusals.
- **CONFIRM** — `match=True (19,250 rows recorded, 19,250 now)`, `MATCH — re-running the stored
  statement returns the same rows`. The same id comes back from the live endpoint.

---

## U11b · The lint and the eval · 11 s
**5:00** 4:04–4:15 · **3:00** cut

- **SHOW** — the MCP client: `lint_answer` on the stock-client script's rejected manager answer (the
  text lives in `scripts/stage2_mcp_client.py`), verdict `rejected (2 rejections)`. Then terminal
  `make eval`, last three lines. Slide 13 is the summary card.
- **SAY** — A manager answer that claims what the logs cannot measure is rejected by the lint. And the
  eval scores 15 of 15 questions against golden SQL.
- **DEMONSTRATES** — the two rules from the brief turned into code: no invented impact, and every
  figure traceable. Enforced, not promised.
- **CONFIRM** — `verdict: rejected (2 rejections)` · `score: 15/15 questions`,
  `figures: 19/19 reproduced (0 wrong) | refusals exercised: 6` · `make check` 101/101.

---

## U12 · A billion rows, searched where they sit · 22 s
**5:00** 4:15–4:37 · **3:00** cut

- **SHOW** — slide 15. **Do not run the bench on camera**: about 1.5 minutes per slice, network-bound.
- **SAY** — Scale: the organisers' billion-row OTel file, 41 gigabytes on S3, is never downloaded. Ten
  seconds of it, 5,275,597 rows, index in place in 60 seconds; a phrase search then takes 13
  milliseconds. Thirty seconds of data crashed the server, and we say so.
- **DEMONSTRATES** — the huge-datasets bonus, and the disclosure that comes with it: the crash is
  reported, not hidden.
- **CONFIRM** — 1,000,000,000 rows · 41 GB · 1,624 row groups · footer read in about 2 s · the
  10-second slice: 5,275,597 rows from 10 row groups, built in 60 s, 136 MB on disk · phrase + facet
  13 ms, 290,473 hits · the 30 s and 60 s slices crash. Machine-dependent: 16 vCPU, about 6 MiB/s to
  S3 — on the slide, not in the narration.

---

## U13a · The data wins · 7 s
**5:00** 4:37–4:44 · **3:00** cut

- **SHOW** — slide 16, the middle card ("The brief vs the data").
- **SAY** — The brief said twelve alert categories; the data has 42, and the organisers agreed: the
  data wins.
- **DEMONSTRATES** — we checked the brief against the corpus instead of trusting it, and raised the
  discrepancy with the challenge owner.
- **CONFIRM** — 12 categories and 5 levels (the brief) against 42 and 6 (measured); the Q&A ruling is
  in `docs/process/PLAN.md` §13.

---

## U13b · Close · 10 s
**5:00** 4:44–4:54 · **3:00** 2:46–2:56

- **SHOW** — slide 16 for four seconds, then slide 17 ("Run it yourself") with the repo URL, which
  holds as the silent end card.
- **SAY** — The ownership map is ours, and no answer states a cost. It all rebuilds in about 20
  seconds. SQL computes; the LLM explains.
- **DEMONSTRATES** — what we own up to, and how fast the whole thing rebuilds. Ends on the tagline.
- **CONFIRM** — slide 16: 23 ownership rows, fictional teams, 100% coverage, 84,253 ASSERT lines
  labelled normal · slide 17: about 20 s for `make bootstrap`.

---

## Timing

Spoken words per unit, numbers expanded as read aloud, against each cut. At 140 wpm the 5:00 version
needs 295 s of narration inside 294 s: take the difference out of the end card and the screen time
around each take, not out of the words.

| Unit | Words | Needs at 150 wpm | 5:00 | 3:00 |
| --- | ---: | ---: | ---: | ---: |
| U1 | 38 | 15.2 s | 16 s | 16 s |
| U2 | 71 | 28.4 s | 31 s | 30 s |
| U3 | 38 | 15.2 s | 17 s | cut |
| U4 | 43 | 17.2 s | 19 s | cut |
| U5 | 50 | 20.0 s | 22 s | 21 s |
| U6 | 27 | 10.8 s | 11 s | cut |
| U7 | 71 | 28.4 s | 30 s | 30 s |
| U8 | 67 | 26.8 s | 28 s | 28 s |
| U9 | 68 | 27.2 s | 29 s | cut |
| U10 | 77 | 30.8 s | 32 s | 32 s |
| U11a | 20 | 8.0 s | 9 s | 9 s |
| U11b | 26 | 10.4 s | 11 s | cut |
| U12 | 52 | 20.8 s | 22 s | cut |
| U13a | 17 | 6.8 s | 7 s | cut |
| U13b | 23 | 9.2 s | 10 s | 10 s |
| **Total** | **688 (5:00) · 417 (3:00)** | **275 s · 167 s** | **294 s + 6 s card** | **176 s + 4 s card** |

---

## Do not say

- **136,209** or **5h43m** — that is the burst cut at 23:00. The burst is **152,183** lines.
- **"12th by blast radius"** for DTLB without qualification: `make demo` W1 M2 puts it 12th on the
  combined blast-radius-plus-persistence ranking, and it is **1st** by lines. Slides 4 and 11 say 12th
  on the combined measure.
- **DTLB figures from `top_signatures(by="lines")`** in the client: that call ranks signature ×
  midplane, so its top row is DTLB on `R30-M0` alone (152,193 lines), not the corpus-wide 152,734 of
  slides 4 and 9. Use `search_logs` (U5) or `make demo` W1 E1.
- **"ciod is growing"** as a measured fact: its slope is +14.8 a week across the corpus and all its
  incidents fall in the last nine weeks, but its final week holds 18. Say **"still active"**, as
  slide 10 does.
- **Any cost, downtime, customer, revenue or SLA figure** — and no "saves", "outage" or "impact"
  claim. The logs cannot support one, and the manager lint rejects it.
- **"The agent never sees the labels"** about BGL: its label is part of the data. The claim holds only
  for `anomaly_labels.txt` (U10).
- **"Healed"** or **"fixed"** for Lustre: the logs show it stopped, not why.

---

## Provenance: where every on-screen number comes from

Kept out of the units so the recording sheet stays readable. Every figure is printed by one of these.

| Unit | Figures | Source |
| --- | --- | --- |
| U2 | 152,183 / 1 node / 2005-06-11 17:17→23:39 | `make smoke` §4b, §4 |
| U2 | 44% of alert lines | slide 3 (`make smoke` §4 prints `pct_of_alert_lines` 43.67) |
| U2 | 49,154 lines on 22,529 nodes | `make smoke` §4b |
| U2 | 348,460 → 19,250 (and 1,377 per signature) | `make smoke` §2 |
| U3 | 12 tools; the endpoint URL | `make check` (stock-client script); slides 6, 7 |
| U4 | 4,747,963 / 4,747,963 / 348,460; the refusal | `make check`; slide 8 |
| U5 | 152,734 phrase matches and the operator | `make check`; `make demo` W1 E1, E2; slides 4, 9 |
| U5 | 117 incidents; 99.64% on one node | `make demo` W1 E1 (`top_node_pct`); slides 4, 9 |
| U5 | `E-55EF08`; R30-M0, 152,182 lines, 6:21:47.98 | `make check`; slides 9, 13 |
| U6 | 132 / 117 / 57 | `make demo` W1 E4; slide 9 |
| U7 | Lustre 3,667 · ciod 3,638 · at most 8 nodes in one | `make demo` W1 L2; slides 4, 10 |
| U7 | 91.09% of lines · 81.61% of alert lines · 51.7% and 48% of incidents | `make demo` W1 L1, L3; slide 10 |
| U7 | Lustre 1,872 / 1,244 / 551, 0 in the last 9; ciod all 3,638 in the last 9 | `make demo` W1 L4, L4b; slide 10 |
| U8 | 348,460 → 19,250, 18.1 lines per incident | `make demo` W1 M1; slide 11 |
| U8 | risk 1 = KERNRTSP, 3,394 nodes, 124 days; DTLB risk 12 | `make demo` W1 M2; slides 4, 11 |
| U8 | the "Not established" line | `make demo` W1, end of the manager section; slide 11 |
| U9 | 188 = 186 + 2; 184 in 8 tracebacks; 2 token incidents | `make smoke` §6, §6b; `make demo` W2 M1, E2; slide 12 |
| U9 | 0.2340 vs 0.2341 s | `make demo` W2 E1; `make validate` §1; slides 12, 14 |
| U9 | 50.72 / 41.81 / 31.27 / 29.46, 26.69 at 5th, median 19.74 | `make demo` W2 L1, L2; slide 12 |
| U10 | 0 tools, 0 relations, 0 columns hold the labels; positions 1–4 of 2,069 | `make validate` §0, §1; slide 14 |
| U10 | chance 1 in 761,325,852,001 (spoken as "about 1 in 761 billion") | `make validate` §1; slide 14 |
| U10 | 99.9998% agreement; precision 0.999991; 0.4065 for a level filter; 13/13 | `make validate` §2; slide 14 |
| U11a | `match=True (19,250 recorded, 19,250 now)` | `make check`; slide 13 |
| U11b | `rejected (2 rejections)`; 15/15; 19/19; 6 refusals; 101/101 | `make check`, `make eval`; slide 13 |
| U12 | 1B rows · 41 GB · 1,624 row groups · footer ~2 s · 5,275,597 rows in 60 s · 13 ms | `make bench`, `make bench-ladder`; `bench/README.md`; slide 15 |
| U13a | 12 vs 42 categories, 5 vs 6 levels | `make smoke`, `docs/data-notes.md`; the Q&A ruling |
| U13b | 23 ownership rows, 100% coverage; 84,253 ASSERT lines labelled normal | the `ownership` tool; `docs/data-notes.md`; slides 16, 17 |
