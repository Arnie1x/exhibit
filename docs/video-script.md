# Video script — 5 minutes, two people, five clips

Team **Logging off Early** · SchubKI National AI Hackathon 2026 · track 04 · deadline 18 Oct 23:59

**The form asks for exactly four things:** the working workflow, the agent calling your tools, the
three role-specific answers, and the executed queries and results supporting them. This script is
those four things in order, plus an opening and a closing line. Nothing else goes in the video.

**How the two of you work:** record the **screens first**, then record **voice-over** on top of them.
Do not narrate live while driving a terminal — that is where takes die. Each of you narrates your own
clips, and each clip is recorded as its own take.

| Clip | Covers | Narrator | Screen | Length |
|---|---|---|---|---|
| 1 | **The working workflow** | A | terminal: `make smoke` | 0:00–0:50 |
| 2 | **The agent calling your tools** | B | agent: engineer question | 0:50–1:40 |
| 3 | **The three role-specific answers** | B | agent: lead, manager, the refusal | 1:40–2:40 |
| 4 | **The executed queries and results** | A | agent: the SQL, then verify | 2:40–3:35 |
| 5 | Close | A + B | slide 17 | 3:35–3:50 |

That is **461 spoken words** — 3:18 of talking at a normal pace, 3:50 if you speak slowly — inside a
3:50 window with the screen action. The limit is 5:00, so there is no rush: pause, let the terminal
settle, and let the viewer read a number before you name it.

**A = Arnie. B = Adnan.** Swap freely — just keep each person on the clips they can speak to
naturally, and let the same voice finish a clip it started.

---

## Before you record — 5 minutes, once

1. `make bootstrap smoke` — the numbers in clip 1 should appear (152,183 / 49,154 / 348,460 → 19,250).
2. Connect the MCP client (`.mcp.json` is already in the repo, so `uv run exhibit-mcp` is the server).
   Send one test question and confirm the tool calls appear in the transcript.
3. Terminal: 18 pt font, 120+ columns, nothing on screen showing `.env` or an IP other than
   `127.0.0.1`.
4. Do a 15-second test recording of voice + screen together. If the mic is quiet, fix it now.
5. **Have the outputs primed**: the four agent answers below already asked once, in one session, in
   this order — so if a live take stumbles you can scroll back rather than retype.

---

## CLIP 1 · The working workflow · 50 s · **A**

**SCREEN** — terminal. Type `make smoke`, let it finish, leave the output on screen.
Scroll so the two headline sections are visible: the alert-line total and the one-node burst.

**SAY**

> We start with the data. Two public corpora: BGL, four point seven million lines from a
> supercomputer, and OpenStack, two hundred thousand lines from a cloud. `make smoke` asks the
> database three questions so we can see whether the numbers still hold after a reload.
>
> Here is the one that matters. One node wrote 152,183 alert lines in a single evening — forty-four
> percent of every alert in the corpus. Days later, a fleet-wide event touched 22,529 nodes and wrote
> only 49,154 lines. So ranking by line count points at the wrong machine. We count incidents
> instead: 348,460 alert lines become 19,250 incidents at a five-minute gap.

**WHY THIS CLIP EXISTS** — it is the form's first requirement: the workflow running, on real data,
producing real numbers. It also states the project's thesis before anything else is shown.

**CHECK BEFORE MOVING ON** — 152,183 · 49,154 across 22,529 nodes · 348,460 → 19,250.

---

## CLIP 2 · The agent calling your tools · 50 s · **B**

**SCREEN** — the agent client, with the tool calls visible in the transcript. Keep it scrolled so the
tool-call lines and the answer are both on screen.

**PROMPT** (ask it once, then leave it):

> As the engineer: search the BGL logs for the phrase "data TLB error interrupt". How many lines
> match in total? Then tell me how many incidents that is at a five-minute gap, and how concentrated
> it is on a single machine. Show me the evidence.

**Start with the phrase search — do not ask for "the problem with the most lines".** That phrasing
sends the agent to `top_signatures`, which ranks at **signature × midplane** grain; its top row is
DTLB *inside* `R30-M0`, which is **152,193 lines and 12 nodes**, not the corpus-wide 152,734 across
541 nodes that slide 9 shows. Both numbers are right, for different questions, and the tool states
its grain in the result notes — but on camera the figure has to match the slide. The phrase search
gives 152,734 directly.

**SAY**

> Now the same corpus through the agent. Exhibit is an MCP server with twelve tools. The agent never
> writes SQL — it picks a tool, and the database does the work.
>
> I'm asking as the engineer: what is the loudest BGL problem, how many incidents is it really, and
> how concentrated is it? Watch the tool calls: a phrase search, then episodes at a five-minute gap,
> then the deepest incident in the corpus.
>
> The answer: 152,734 lines, but only 117 incidents, and 99.64 percent of those lines come from one
> node. One machine, not the fleet. And every claim carries an evidence ID.

**WHY THIS CLIP EXISTS** — the form's second requirement: the agent choosing and calling your tools.
The tool-call lines in the transcript are the point of the clip, so do not crop them out.

**CHECK BEFORE MOVING ON** — 152,734 lines · 117 incidents · 99.64% from one node · an evidence ID.

---

## CLIP 3 · The three role-specific answers · 60 s · **B**

**SCREEN** — the same agent session, three short answers one after another. Cut between them; each
answer should sit on screen for about 15 seconds.

**PROMPTS** — ask these three, in this order, in the same session:

> As the team lead, rank BGL signatures by incident count, top two, with the owning team and whether
> each one is still active.

> As the manager, rank BGL risks by blast radius and persistence, top two, and tell me where the
> most-lines problem ranks.

> As the lead, search the raw logs for "ciod".

**SAY**

> Same corpus, same question, three readers.
>
> As the team lead — who is deliberately barred from reading log lines at all — the ranking by
> incidents looks different: Lustre mount failures at 3,667 and a ciod socket error at 3,638. The
> trend separates them. Lustre stopped after three weeks; the ciod socket error is still active, with
> every one of its incidents in the last nine weeks.
>
> As the manager, who sees no log text and no node IDs, the ranking changes again: rts panic first, on
> 3,394 nodes across 124 active days. The data TLB error — first by lines — is twelfth.
>
> Three orderings, three different first problems, one corpus. And when the lead asks for raw log
> text, the database refuses. That is a permission, not a prompt.

**WHY THIS CLIP EXISTS** — the form's third requirement, and the heart of the submission: the same
data answering the same question differently for three readers, with the difference enforced in the
database rather than asked for in a prompt.

**CHECK BEFORE MOVING ON** — Lustre 3,667 · ciod 3,638 · rts panic 3,394 nodes / 124 days · DTLB
twelfth · one refusal.

**IF THE REFUSAL DOESN'T ARRIVE** — it is the last line of the clip, so a cut to the sentence
"It's a permission, not a prompt" still works over the refusal text from `make demo`. Do not retake
the whole session for it.

---

## CLIP 4 · The executed queries and the results behind the answers · 55 s · **A**

**SCREEN** — the agent session, then the verification. Two beats:
1. Ask for the query behind the engineer answer, so the SQL text is on screen.
2. Then verify. Either the agent calls `verify_evidence`, or you run the stock-client script and hold
   on its `re-running the first answer from the evidence ledger` block.

**PROMPT**

> Show me the exact SQL behind your engineer answer, then verify that answer's evidence ID.

**SAY**

> Every one of those numbers travels with the query that produced it. The tool result carries the
> SQL, the parameters, the true total and an evidence ID — so an answer is an envelope, not a
> sentence.
>
> Here is the SQL behind the engineer's answer, run against the same index. And here is the check:
> verify evidence re-runs the stored statement and compares the result hash. Match — 19,250 rows
> recorded, 19,250 now.
>
> The same ID comes back from the live endpoint, which a judge can point a client at without cloning
> anything.

**WHY THIS CLIP EXISTS** — the form's fourth requirement. This is also the answer to the question
every judge has: "why should I believe the LLM?" Because it is not the one computing.

**CHECK BEFORE MOVING ON** — SQL text visible · `MATCH` · `19,250 rows recorded, 19,250 now`.

---

## CLIP 5 · Close · 15 s · **A + B**

**SCREEN** — slide 17 ("Run it yourself") with the repo URL, held to the end.

**SAY** (A starts, B finishes — or one voice, whichever is cleaner)

> Two students, forty-eight hours. BGL and OpenStack, one database, twelve tools, three roles.
> Everything on screen came from a query that ran.
>
> SQL computes. The LLM explains.

**CHECK** — the repo URL is legible and stays up for at least 4 seconds.

---

## Assembly

1. Lay clips 1→5 in order. Trim dead air at the head and tail of each.
2. Total target **under 4:30**; the limit is 5:00. If you are over, cut clip 4's third paragraph
   (the live-endpoint sentence) first, then clip 3's manager sentence about DTLB being twelfth.
3. Add the deck slides only where they help: clip 3 over slide 2 ("Three readers"), clip 4 over
   slide 13 ("Every number travels with its query"), clip 5 on slide 17. Everything else is the
   terminal and the agent — that is what the form asks to see.
4. Export 1080p, audio normalised, filename `exhibit-demo.mp4`.

**If the challenge still wants a 3:00 cut:** clips 1, 2, 3 and 5, dropping clip 4 and trimming
clip 3 to the lead and manager answers. Same takes, no second session.

---

## Do not say

- **136,209** — an early figure from a window cut at 23:00. The burst is **152,183**.
- **"The DTLB problem is 152,193 lines."** Say **152,734**. 152,193 is the `R30-M0` slice alone:
  `top_signatures` ranks signature × midplane, so its top row is DTLB inside one midplane. If a judge
  asks about the difference, one sentence answers it — *"152,734 is the whole signature across 541
  machines; the ranking tool groups by signature and midplane, because that is the grain an incident
  is coalesced at, so its top row is the one midplane that produced 152,193 of them."* Both are real;
  they answer different questions, and the demo prints both.
- **"12th by blast radius"** without qualification — DTLB is 12th on blast radius *plus persistence*,
  and **1st** by lines.
- **Any cost, downtime, customer or revenue figure.** The logs cannot support one.
- **"The agent never sees the labels"** about BGL — its label is in the data. That claim is only true
  of the OpenStack answer key, which is not in this video.
- **"Fixed"** or **"healed"** for Lustre — the logs show it stopped, not why. Say "stopped".

---

## Where the spoken numbers come from

| Number | Command |
|---|---|
| 4,747,963 / 207,812 lines; 152,183 burst; 49,154 across 22,529 nodes; 348,460 → 19,250 | `make smoke` |
| 152,734 lines; 117 incidents; 99.64% on one node | `make demo` W1 E1; the agent's `search_logs` + `episodes` |
| Lustre 3,667 · ciod 3,638; 3,394 nodes / 124 days; DTLB 12th | `make demo` W1 L2, L4, M2; the agent's `top_signatures` |
| 19,250 rows recorded and now; `MATCH` | `make check`; the agent's `verify_evidence` |
| 42 categories vs the brief's 12 | `make smoke`, `docs/data-notes.md` |

**One number to be ready to explain, not to say:** `152,193` (the `R30-M0` midplane slice) against
`152,734` (the whole signature). See the note under clip 2.

Every figure also appears on a slide, and slides 3, 4, 9–13 carry their own provenance in
`docs/slides.md`.
