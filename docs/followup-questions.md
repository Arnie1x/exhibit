# Follow-up questions to the challenge owners (Discord)

From tonight's Q&A — three that we ran out of slot for. Short, concrete, no pressure on the
reading. (Arnie to post; keep it in this shape.)

---

Hi — Logging off Early (track 04) here. Three quick ones from tonight that we didn't get to:

1. **Ground-truth labels**: the corpora ship with a label column and `anomaly_labels.txt`. We keep
   them strictly away from the agent — no MCP tool and no role view can reach them — and use them
   only afterwards, as a scorecard (our OpenStack validation section: the four labelled anomalies
   rank 1-4 by spawn time *without* the agent seeing them). We disclose this in
   `docs/disclosure.md`. Is that the intended reading — labels as validation ground truth, never
   as agent input?

2. **Ownership granularity**: for W1/W2 we build our own ownership map (logger -> service ->
   component, 100% line coverage, documented as our construction). Do you expect
   per-component/per-service granularity like that, or end-to-end ownership of a request path?

3. **Repo visibility**: it is private during the build and goes public at submission (per the
   checklist). If you or the judges would rather clone it earlier, say the word and we'll flip it
   tonight.

Thanks!

---

**Status:** not yet sent. Q4 (labels) is the one that matters — if the answer were "no", we'd drop
the validation framing, not the analysis.
