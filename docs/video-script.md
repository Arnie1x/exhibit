# Video script: run of show (team stage 7)

The recorded demo for team plan §11 stage 7: **5:00 at most** (the Q&A confirmed a five-minute
slot, §13 Q3) **plus a 3:00 cut** (the brief asks for one, §15). It tells the W1 and W2 story of
PLAN.md §9 role by role, with one live query on screen (§15), over the 17-slide Canva deck whose
every figure is listed in `docs/slides.md`. Where `docs/build-plan.md` §10 names prompts or tools
the repo does not have, the repo wins (CLAUDE.md).

Rules this script keeps:

- **Every number** below is printed by `make smoke`, `make demo`, `make check`, `make eval`,
  `make validate` or `make bench`, and each unit names the command and section. Re-run on 18 Oct
  against SereneDB 26.09.1.3 after a fresh `make bootstrap` (15.8 s on the Windows box): every
  figure matched. The live endpoint was called the same day and returned the same evidence IDs as
  the local run (`E-55EF08` on both).
- **No impact claims.** The narration states no cost, downtime, customer, revenue or SLA figure.
  Those words appear on screen only in the manager's "Not established" line (U8, slide 11), the
  lint rejecting them (U11b, slide 13) and the limits slide (slide 16).
- **Ground truth is disclosed** (U10): both corpora ship with answer keys; the OpenStack one never
  reaches the agent, and BGL's label is part of the data, so it is tested for agreement, not
  blindness.
- **Timing.** Each unit is one narration take. Its time in each cut holds its spoken words at 150
  words per minute, counting numbers as they are read aloud ("152,183" is seven words). The table
  at the end lists the counts.

## Before recording

1. `make bootstrap` (about 20 s), then `make smoke`, `make demo`, `make check`, `make eval`,
   `make validate`: all green, numbers as in the units below. On Windows there is no `make`: run
   each recipe by hand as the README says (`MSYS_NO_PATHCONV=1`, `PYTHONUTF8=1`).
2. Connect a stock MCP client two ways and check that each lists 12 tools: locally, through the
   repo's `.mcp.json` (`exhibit`: `uv run exhibit-mcp`, stdio), and remotely, through its
   `exhibit-demo` entry (`https://hermes.bushbaby-platy.ts.net:10000/mcp`, streamable HTTP). Record
   the local one; show the remote one in U3. The persona is the tools' `persona` argument; the
   server maps it to a SereneDB role, so the database, not the prompt, decides what each persona
   can read.
3. Record the fallbacks first: the full `make demo` output and the full output of
   `uv run python scripts/stage2_mcp_client.py` (the stock-client script). Every number the MCP
   client shows in this script is also printed by one of those two. If the model picks other tools
   in a take, cut to the fallback; the narration does not change. The live endpoint failed once in
   six calls on 18 Oct (`SSE stream ended without a response`); if it does on camera, retake.
4. Terminal: 18 pt font, at least 120 columns (the `make demo` tables are wide), commands typed
   ahead of time. Nothing on screen shows `.env` or an IP address other than 127.0.0.1; the only
   hostname shown is the public demo endpoint, which the README already publishes.
5. Narration: record each unit as its own take, so the 3:00 cut is an edit, not a second recording.
6. The deck: the Canva presentation "Exhibit: SQL computes, the LLM explains", 17 slides; the
   speaker notes on each slide are the narration below.

## Run of show

| Unit | 5:00 | 3:00 | Screen | Spoken figures |
| --- | --- | --- | --- | --- |
| U1 Open | 0:00–0:16 | 0:00–0:16 | Slides 1, 2 | none |
| U2 Lines are not incidents (live) | 0:16–0:47 | 0:16–0:46 | Terminal: `make smoke`; slide 3 | 152,183 · 44% · 22,529 · 49,154 · 348,460 → 19,250 |
| U3 How it works, how to connect | 0:47–1:04 | cut | Slides 5, 6, 7; MCP client (local, then live) | twelve tools |
| U4 Roles in the database | 1:04–1:23 | cut | Slide 8; MCP client | none |
| U5 W1, the engineer | 1:23–1:45 | 0:46–1:07 | Slide 9; MCP client | 152,734 · 117 · 99.64% |
| U6 The gap is a parameter | 1:45–1:56 | cut | Slide 9; `make demo` W1 E4 | 132 · 117 · 57 |
| U7 W1, the team lead | 1:56–2:26 | 1:07–1:37 | Slide 10; MCP client; `make demo` W1 L3, L4 | 91.1% · 51.7% · 3,667 · 3,638 |
| U8 W1, the manager | 2:26–2:54 | 1:37–2:05 | Slide 11; `make demo` W1 M1, M2 | 3,394 · 124 |
| U9 W2, OpenStack | 2:54–3:23 | cut | Slide 12; `make demo` W2 | 188 · 8 · 2 · 0.2340 · 0.2341 · 50.72 · 29.46 |
| U10 Ground truth | 3:23–3:55 | 2:05–2:37 | Terminal: `make validate`; slide 14 | 1 to 4 of 2,069 · 1 in 761 billion · 99.9998% |
| U11a Re-run any number | 3:55–4:04 | 2:37–2:46 | Slide 13; MCP client: `verify_evidence` | none |
| U11b Lint and eval | 4:04–4:15 | cut | Slide 13; MCP client: `lint_answer`; `make eval` | 15 of 15 |
| U12 A billion rows | 4:15–4:37 | cut | Slide 15 | 41 GB · 5,275,597 · 60 s · 13 ms |
| U13a The data wins | 4:37–4:44 | cut | Slide 16 | twelve · 42 |
| U13b Close | 4:44–4:54 | 2:46–2:56 | Slides 16, 17 | 20 s |
| End card, silent | 4:54–5:00 | 2:56–3:00 | Slide 17 (repo URL) | — |

The 3:00 cut is U1, U2, U5, U7, U8, U10, U11a and U13b, in that order and word for word: the live
query, the three roles on W1, the ground-truth disclosure and one re-run, which also names the live
server. It uses the same takes as the 5:00 version with less screen time around each, and no unit
in it depends on a cut one. Slide 4 ("One corpus, three rankings") is the summary card for U5 to U8
and is not narrated on its own.

## Units

### U1 · Open · 16 s

- **5:00** 0:00–0:16 · **3:00** 0:00–0:16
- **Screen:** slide 1 (cover), then slide 2 ("One question, three readers") from "for the engineer".

> **Say:** Exhibit answers one question three ways: for the engineer who fixes it, the lead who staffs it, and the manager who decides. SQL computes, the LLM explains: every number on screen comes from a query you can re-run.

- **Numbers:** none.

### U2 · Lines are not incidents (the live query) · 31 s

- **5:00** 0:16–0:47 · **3:00** 0:16–0:46
- **Screen:** terminal. Type `make smoke` and let it run. Hold on section 4b (the money comparison),
  then section 2. In the edit, box each figure as it is spoken. Slide 3 as a two-second end card in
  the 5:00 version. This is the team plan §15 "real query, real number on screen".

> **Say:** Live, on SereneDB. One node wrote 152,183 alert lines in one evening: 44 percent of all alerts. Days later, one event hit 22,529 nodes with only 49,154 lines. Lines point at the wrong one. So we count incidents: at a five-minute gap, 348,460 alert lines become 19,250.

- **Numbers on screen:**
  - 152,183 lines, 1 node, 2005-06-11 17:17 → 23:39: `make smoke` §4b and §4; slide 3.
  - 44% of alert lines: slide 3 (`make smoke` §4 prints `pct_of_alert_lines` 43.67).
  - 49,154 lines on 22,529 nodes, 2005-06-14: `make smoke` §4b; slide 3.
  - 348,460 alert lines → 19,250 incidents (5 minutes, signature × midplane) → 1,377 (signature
    only): `make smoke` §2; slide 3.

### U3 · How it works, and how to connect · 17 s

- **5:00** 0:47–1:04 · **3:00** cut
- **Screen:** slide 5 (architecture) and slide 6 (the twelve tools), then the local MCP client's
  tool list; slide 7 ("Three ways to connect"), then a second client window connected to the live
  endpoint with the same tool list.

> **Say:** Under the hood: an MCP server with twelve tools. SereneDB searches and counts; every tool returns its query and an evidence ID. Clone the repo and the server is registered, or point any client at our live endpoint.

- **Numbers on screen:** 12 tools (`describe_data` … `lint_answer`): `make check` (the stock-client
  script prints the list); slide 6. The endpoint URL and "Tested 18 Oct": slide 7.

### U4 · Roles in the database · 19 s

- **5:00** 1:04–1:23 · **3:00** cut
- **Screen:** slide 8 for two seconds, then the MCP client.
- **Type:** `Count BGL lines grouped by team three times: as persona engineer, as lead, as manager. Then, as the lead, search BGL for "ciod".`
- **Expected calls:** `count_events(dataset="bgl", group_by="team", persona=…)` three times, then
  `search_logs(dataset="bgl", query="ciod", persona="lead")`.

> **Say:** Roles live in the database, not in the prompt. One call, three personas: the engineer counts every row, the lead gets lines already summed by team, and the manager sees only alert lines. Ask for log text as the lead, and SereneDB refuses.

- **Numbers on screen:**
  - engineer `4,747,963 matching rows`; lead `4,747,963 sum of lines`; manager
    `348,460 sum of alert_lines`: `make check` (stock-client script, "the same question, asked as
    the three personas"); slide 8.
  - the lead's search: `NOT PERMITTED for lead@exhibit_lead`: `make check`; slide 8.

### U5 · W1, the engineer · 22 s

- **5:00** 1:23–1:45 · **3:00** 0:46–1:07
- **Screen:** slide 9, then the MCP client. Overlay the `make demo` W1 E1 row for DTLB (it carries
  `top_node_pct`).
- **Type:** `Persona engineer. Which BGL problem should we fix first? Search the phrase "data TLB error interrupt", count its episodes at a 5-minute gap, then show the deepest episode in the corpus.`
- **Expected calls:** `search_logs(dataset="bgl", query="data TLB error interrupt", mode="phrase")`,
  `episodes(dataset="bgl", gap_minutes=5, signature="data TLB error interrupt")`,
  `episodes(dataset="bgl", gap_minutes=5, limit=1)`.

> **Say:** Question one: what do we fix first? The engineer searches the loudest signature, data TLB error interrupt: 152,734 lines. Episodes make that 117 incidents, and 99.64 percent of the lines come from one node. One machine, not the fleet.

- **Numbers on screen:**
  - 152,734 matching rows, operator `phrase (ts_phrase)`: `make check`; `make demo` W1 E1, E2;
    slides 4, 9.
  - 117 incidents at a 5-minute gap: `make check`; `make demo` W1 E1; slides 4, 9.
  - 99.64% of the lines on one node: `make demo` W1 E1 (`top_node_pct`); slides 4, 9.
  - `E-55EF08`: 19,250 incidents in total; the deepest is `data TLB error interrupt` on R30-M0,
    152,182 lines, 1 node, 6:21:47.98: `make check`; slides 9, 13. Shown, not read out. The id is
    stable: this call returns `E-55EF08` on every run, locally and on the live endpoint.

### U6 · The gap is a parameter · 11 s

- **5:00** 1:45–1:56 · **3:00** cut
- **Screen:** slide 9 (the gap box, bottom right), or terminal `make demo` W1 E4.

> **Say:** The count depends on the gap: 132, 117 or 57 incidents at one, five or sixty minutes. So every answer states its gap.

- **Numbers on screen:** 132 / 117 / 57 (per signature × midplane): `make demo` W1 E4; slide 9.

### U7 · W1, the team lead · 30 s

- **5:00** 1:56–2:26 · **3:00** 1:07–1:37
- **Screen:** the MCP client for the ranking, then slide 10 (team shares and the weekly chart). The
  terminal `make demo` W1 L3 (team shares), L4 (weekly trend) and L4b (the chart's bars) are the
  fallback.
- **Type:** `Persona lead. Rank BGL signatures by episodes at a 5-minute gap, top 2, with the owning team.`
- **Expected call:** `top_signatures(dataset="bgl", persona="lead", by="episodes", limit=2)`.
- The weekly trend per signature comes from `make demo` L4 and L4b, not from the `trend` tool: the
  lead's view is daily, and `trend(bucket="week")` as the lead returns NOT PERMITTED by design.

> **Say:** The lead gets no raw lines: signatures by owning team, from our fictional ownership map. Compute-platform owns 91.1 percent of lines but 51.7 percent of incidents. By incidents, two signatures lead: Lustre mount failures, 3,667, and a ciod socket error, 3,638. The weekly chart splits them: Lustre stopped after three weeks; every ciod incident falls in the last nine.

- **Numbers on screen:**
  - Lustre 3,667 and ciod 3,638 incidents, at most 8 nodes in one, teams `compute-platform` and
    `workload-runtime`: MCP `top_signatures`; `make demo` W1 L2; slides 4, 10.
  - compute-platform 91.09% of lines (L1), 81.61% of alert lines, 51.7% of incidents;
    workload-runtime 48%: `make demo` W1 L1, L3; slide 10.
  - Lustre: 3 active weeks (1,872 · 1,244 · 551), 0 in the last 9; ciod: 8 active weeks, all
    3,638 in the last 9, peak week 1,110, slope 14.806 a week: `make demo` W1 L4, L4b; slide 10.

### U8 · W1, the manager · 28 s

- **5:00** 2:26–2:54 · **3:00** 1:37–2:05
- **Screen:** slide 11, then terminal `make demo` W1 M1, M2 and the closing "Not established" line
  (run under the manager role, which has no log text and no node IDs). Slide 4 as the summary card.

> **Say:** The manager sees no log text and no node IDs, only risks ranked by blast radius and persistence. First: the rts panic, owned by compute-platform, on 3,394 nodes across 124 days. The data TLB error, first by lines, is twelfth. A slow burn across the fleet outranks a fire on one machine. What the logs cannot measure is marked not established.

- **Numbers on screen:**
  - 348,460 alert lines → 19,250 incidents, 18.1 lines per incident: `make demo` W1 M1; slide 11.
  - risk position 1: `KERNRTSP`, KERNEL, compute-platform, 3,394 nodes, 124 active days; its
    signature is `rts panic! - stopping execution`: `make demo` W1 M2; slides 4, 11.
  - DTLB (`KERNDTLB`): lines position 1, risk position 12, 541 nodes, 11 active days:
    `make demo` W1 M2; slides 4, 11.
  - "Not established by the logs: cost, downtime, impact on jobs or users, root cause.": `make demo`
    W1, end of the manager section; slide 11. Shown, not read out.

### U9 · W2, OpenStack · 29 s

- **5:00** 2:54–3:23 · **3:00** cut
- **Screen:** slide 12, then terminal `make demo` W2 M1 (problems), E1 (latency) and L1 (spawn
  ranking). The ranking can also come from the MCP client:
  `durations(dataset="openstack", persona="lead", by="spawn_s", limit=4)`.

> **Say:** On OpenStack: were the instances meant to be slow actually slow? The 188 error and critical lines are 8 tracebacks of one image-cache bug, plus 2 token-validation incidents. Latency cannot see the anomaly: 0.2340 against 0.2341 seconds. Lifecycle duration can: the four slowest spawns run 50.72 down to 29.46 seconds.

- **Numbers on screen:**
  - 188 ERROR + CRITICAL lines (186 + 2): `make smoke` §6; `make demo` W2 E2; slide 12.
  - 184 of them are 8 tracebacks of `InvalidDiskInfo`, 8 incidents, platform-services; the other 4
    are token validation (6 lines with its 2 WARNING, 2 incidents, the only 2 CRITICAL lines),
    identity: `make demo` W2 M1; `make smoke` §6b; slide 12.
  - mean latency 0.234 s (abnormal) vs 0.2341 s (normal): `make demo` W2 E1; 0.2340 vs 0.2341 in
    `make validate` §1; slides 12, 14.
  - spawn 50.72, 41.81, 31.27, 29.46 s at positions 1–4, 26.69 s at 5, median 19.74 s:
    `make demo` W2 L1, L2; slide 12.

### U10 · Ground truth, kept out of the agent's reach · 32 s

- **5:00** 3:23–3:55 · **3:00** 2:05–2:37
- **Screen:** terminal, `make validate`. Hold on section 0 (the two PASS lines: no tool reads
  labels, no relation or column holds them), then section 1 (positions 1–4), then section 2
  (agreement). Slide 14 as the summary card.

> **Say:** Both corpora ship with answer keys. OpenStack's never reaches the agent: no tool reads it, no table holds it; a separate script scores us. The lead's duration ranking puts its four labelled instances at positions 1 to 4 of 2,069: about 1 in 761 billion by chance. BGL's label is part of the data, so there we test agreement: text-only signatures match it on 99.9998 percent of lines.

- **Numbers on screen:**
  - none of the 12 tools reads labels; 0 relations, 0 columns hold `anomaly_labels.txt`:
    `make validate` §0; slide 14.
  - positions [1, 2, 3, 4] of 2,069; chance 1 in 761,325,852,001 (spoken as "about 1 in 761
    billion"): `make validate` §1; slide 14.
  - 99.9998% line agreement over 4,747,963 lines; precision 0.999991, recall 0.999983, against
    0.4065 precision for a FATAL-or-FAILURE filter: `make validate` §2; slide 14.
  - `13/13 expectations hold`: `make validate`; slide 14.

### U11a · Re-run any number · 9 s

- **5:00** 3:55–4:04 · **3:00** 2:37–2:46
- **Screen:** slide 13, then the MCP client. **Type:** `Verify evidence E-55EF08.`
- **Expected call:** `verify_evidence(evidence_id="E-55EF08")`.

> **Say:** Any number can be checked: verify evidence re-runs the stored query. Match, and the live server gives the same ID.

- **Numbers on screen:** `E-55EF08: match=True (19,250 rows recorded, 19,250 now)`, `MATCH`:
  `make check`; slide 13. The same id from the live endpoint: slide 7.

### U11b · Lint and eval · 11 s

- **5:00** 4:04–4:15 · **3:00** cut
- **Screen:** the MCP client: `lint_answer` on the stock-client script's rejected manager answer
  (the text in `scripts/stage2_mcp_client.py`), verdict `rejected (2 rejections)`. Then terminal
  `make eval`, last three lines. Slide 13 as the summary card.

> **Say:** A manager answer that claims what the logs cannot measure is rejected by the lint. And the eval scores 15 of 15 questions against golden SQL.

- **Numbers on screen:**
  - `verdict: rejected (2 rejections)`: `make check`.
  - `score: 15/15 questions`, `figures: 19/19 reproduced (0 wrong) | refusals exercised: 6`:
    `make eval`; slide 13. `make check` 101/101: slide 13.

### U12 · A billion rows, searched where they sit · 22 s

- **5:00** 4:15–4:37 · **3:00** cut
- **Screen:** slide 15. The bench is not run on camera (about 1.5 minutes per slice,
  network-bound).

> **Say:** Scale: the organisers' billion-row OTel file, 41 gigabytes on S3, is never downloaded. Ten seconds of it, 5,275,597 rows, index in place in 60 seconds; a phrase search then takes 13 milliseconds. Thirty seconds of data crashed the server, and we say so.

- **Numbers on screen** (slide 15; `make bench`, `make bench-ladder`; `bench/README.md`):
  1,000,000,000 rows, 41 GB, 1,624 row groups, footer read in about 2 s; the 10-second slice:
  5,275,597 rows from 10 row groups, built in 60 s, 136 MB on disk; phrase + facet 13 ms,
  290,473 hits; 30 s and 60 s slices crash. Machine-dependent: 16 vCPU, about 6 MiB/s to S3 (on the
  slide, not in the narration).

### U13a · The data wins · 7 s

- **5:00** 4:37–4:44 · **3:00** cut
- **Screen:** slide 16, the middle card ("The brief vs the data").

> **Say:** The brief said twelve alert categories; the data has 42, and the organisers agreed: the data wins.

- **Numbers on screen:** 12 categories and 5 levels (the brief) against 42 and 6 (measured):
  `make smoke`, `docs/data-notes.md`; the Q&A ruling: PLAN.md §13; slide 16.

### U13b · Close · 10 s

- **5:00** 4:44–4:54 · **3:00** 2:46–2:56
- **Screen:** slide 16 for 4 seconds, then slide 17 ("Run it yourself") with the repo URL, which
  holds as the silent end card.

> **Say:** The ownership map is ours, and no answer states a cost. It all rebuilds in about 20 seconds. SQL computes; the LLM explains.

- **Numbers on screen:** slide 16: 23 ownership rows, fictional teams, 100% coverage (the
  `ownership` tool), 84,253 ASSERT lines labelled normal (`docs/data-notes.md`); slide 17: about
  20 s, `make bootstrap`.

## Timing check

Spoken words per unit, numbers expanded as read aloud, and the seconds they need at 150 words per
minute, against the unit's time in each cut. Counted on the final text above.

| Unit | Spoken words | Needs at 150 wpm | 5:00 | 3:00 |
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
| **Total** | **688 (5:00) · 417 (3:00)** | **275.2 s · 166.8 s** | **294 s + 6 s end card** | **176 s + 4 s end card** |

At 140 words per minute the 5:00 version needs 295 s of narration in its 294 s and the 3:00 cut 179 s of its 176: at that pace, take the difference out of the end card and the screen time around each take, not out of the words.

## Do not say

- **136,209** or **5h43m**: the burst cut at 23:00. The burst is 152,183 lines (CLAUDE.md, data facts).
- **"12th by blast radius"** for DTLB: `make demo` W1 M2 puts it 12th on the combined ranking (risk
  position 12), as slides 4 and 11 say.
- **DTLB numbers from `top_signatures(by="lines")`** in the MCP client: that call ranks
  signature × midplane, so its top row is DTLB on R30-M0 alone (152,193 lines), not the corpus-wide
  152,734 of slides 4 and 9. Use `search_logs` (U5) or `make demo` W1 E1.
- **"ciod is growing"** as a measured fact: its slope over the whole corpus is +14.8 a week and all
  of its incidents fall in the last nine weeks, but its last week has 18. Say "still active", as
  slide 10 does.
- **Any cost, downtime, customer, revenue or SLA figure**, and no "saves", "outage" or "impact"
  claim. The logs cannot support one.
- **"The agent never sees the labels"** about BGL: its label is part of the data. The claim holds
  for `anomaly_labels.txt` only (U10).
- **"Healed"** or **"fixed"** for Lustre: the logs show it stopped, not why.
