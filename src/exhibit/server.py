"""MCP server exposing the tools over stdio.

Run it:  uv run exhibit-mcp        (or: make mcp)
Point a client at it: any MCP client speaking stdio. `scripts/stage2_mcp_client.py` is a
stock-client check that lists the tools and makes one real call.

Every tool takes a ``persona`` (engineer | lead | manager). That is not a label: each persona runs
under its own database role, so a role that may not see a thing gets a refusal from the engine
rather than a story from the model.

Note for MCP 2.x: the class is MCPServer (FastMCP was renamed). ``mcp`` 1.x used
``from mcp.server.fastmcp import FastMCP``; this project is on the 2.x API.
"""
from __future__ import annotations

import json

from mcp.server.mcpserver import MCPServer

from . import analytics, lint, tools

INSTRUCTIONS = """Log intelligence over the BGL and OpenStack corpora, computed in SereneDB.

Every answer comes back as an envelope carrying the rows, the SQL, the bound parameters, the true
total, whether it was truncated, and an evidence id. Quote the evidence id.

Three personas, three different views of the same data -- enforced by database roles, not by
instructions. Ask as the persona whose question you are answering:

* engineer (`exhibit_engineer`) -- raw lines and full-text search: what is broken, on which machine,
  and what the log line actually says;
* lead (`exhibit_lead`) -- per day/hour aggregates, no text: which team's work it is, how it trends;
* manager (`exhibit_manager`) -- risk factors only, no hostnames or instance IDs: what to fix first.

A request a role may not make returns `refused: true` with the reason. Do not retry it as another
persona to work around it; report the refusal.

Rules the server enforces, so do not fight them:
* numbers come from SQL, never from you -- never compute or estimate a figure yourself;
* search runs against an index relation, aggregation against the role's own relation;
* the operator that produced a count is stated in every envelope (term / phrase / any / all);
* `count_events` reports whether it counted rows or summed a measure -- they are different things;
* lines are not incidents: one node produced 152,183 lines in 6h22m while a fleet-wide event
  produced 49,154 lines across 22,529 nodes.

Stage 3 turns that into the analysis surface:

* `episodes` -- collapse lines into incidents at a stated gap. The gap is a parameter for the
  engineer (22,002 incidents at one minute, 14,479 at an hour) and a fixed 5 minutes for the lead
  and manager, whose relations are pre-grouped; the envelope says which, and the refusal names the
  reason rather than silently returning a different number;
* `top_signatures` -- rank by episodes, lines or blast radius, and see all three side by side. This
  is where "ranked by lines" and "ranked by blast radius" disagree in public;
* `trend`, `what_changed` -- movement over time, anchored to the last timestamp in the data (2005
  and 2017), never to today. `what_changed` compares per hour on both sides, so a shorter window
  does not read as a decline;
* `durations` -- OpenStack server lifecycle phases, worst first. The only place the four labelled
  anomalies are visible at all;
* `ownership` -- the team-ownership table we built, checked against the corpus rather than trusted;
* `nearby_events` -- what else was happening around one line. Engineer only;
* `verify_evidence` -- re-runs any stored answer and compares it hash for hash. No number here is
  taken on trust, including the ones this server produced;
* `lint_answer` -- check an answer before you send it. A manager answer may not claim money,
  downtime, customers, revenue or an SLA (quoting them from a log line is allowed, claiming is
  not), and every figure in the Observed block must cite an evidence id that resolves -- with
  deep=true the cited statement is re-run and the figures are looked for in its rows. A rejected
  answer is not an answer: fix it or drop the claim.

Never add up a blast radius: `nodes` is distinct machines per incident, so it is a peak, not a sum.
"""

mcp = MCPServer(
    name="exhibit",
    title="Logging off Early — log intelligence on SereneDB",
    instructions=INSTRUCTIONS,
    version="0.3.0",
)


@mcp.tool(description=(
    "What the given persona can ask, of which data, over what period, grouped how. Call this first. "
    "persona: engineer | lead | manager (default engineer)."))
def describe_data(dataset: str | None = None, persona: str | None = None) -> str:
    return json.dumps(tools.describe_data(persona=persona, dataset=dataset), default=str)


@mcp.tool(description=(
    "Full-text search over one dataset's logs: matching lines with highlighted terms, the true total "
    "match count and an evidence id. engineer only -- the lead and manager roles have no grant on the "
    "relation behind the index and receive a refusal envelope. "
    "mode: term | phrase | any | all (default phrase; any/all take a comma-separated list)."))
def search_logs(
    dataset: str,
    query: str,
    persona: str | None = None,
    mode: str = "phrase",
    limit: int = 10,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> str:
    return json.dumps(
        tools.search_logs(dataset=dataset, query=query, persona=persona, mode=mode, limit=limit,
                           since=since, until=until, level=level, team=team),
        default=str,
    )


@mcp.tool(description=(
    "How many, bucketed by a column of the given persona's view (signature, component, level, team, "
    "problem, ...). On a raw relation it counts rows; on an aggregated one it sums the view's measure "
    "-- the envelope says which. `query` (a full-text predicate) is engineer only. "
    "persona: engineer | lead | manager (default engineer)."))
def count_events(
    dataset: str,
    group_by: str | None = None,
    persona: str | None = None,
    query: str | None = None,
    mode: str = "phrase",
    limit: int = 20,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> str:
    return json.dumps(
        tools.count_events(dataset=dataset, group_by=group_by, persona=persona, query=query,
                           mode=mode, limit=limit, since=since, until=until, level=level,
                           team=team),
        default=str,
    )


@mcp.tool(description=(
    "Collapse log lines into incidents: one signature in one failure domain that did not fall quiet "
    "for longer than gap_minutes. The gap is stated back with the answer -- the same corpus reads as "
    "22,002 incidents at 1 minute and 14,479 at 60. gap_minutes is a parameter only for the engineer, "
    "who holds a grant on the parsed relation; for the lead and manager incidents are pre-grouped at "
    "5 minutes and asking for another gap returns a refusal that says why. "
    "coalesce_by: failure_domain (default) | signature. signature= filters to one signature "
    "(engineer and lead only; the manager's relation names problems by signature_id, and the "
    "refusal says so) -- this is how 132 / 117 / 57 incidents for one signature at gaps of 1 / 5 / "
    "60 minutes is reproduced through the tool."))
def episodes(
    dataset: str,
    persona: str | None = None,
    gap_minutes: int = 5,
    coalesce_by: str | None = None,
    signature: str | None = None,
    limit: int = 20,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> str:
    return json.dumps(
        analytics.episodes(dataset=dataset, persona=persona, gap_minutes=gap_minutes,
                           coalesce_by=coalesce_by, signature=signature, limit=limit,
                           since=since, until=until, level=level, team=team),
        default=str,
    )


@mcp.tool(description=(
    "Rank problems with lines, incidents and blast radius side by side, ordered by `by` "
    "(episodes | lines | nodes). The point of the tool is that the three criteria disagree: this "
    "corpus ranked by lines is a fleet-wide log flood, ranked by blast radius it is a six-hour "
    "one-machine meltdown. Blast radius is always a peak, never a sum."))
def top_signatures(
    dataset: str,
    persona: str | None = None,
    by: str = "episodes",
    gap_minutes: int = 5,
    limit: int = 20,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> str:
    return json.dumps(
        analytics.top_signatures(dataset=dataset, persona=persona, by=by,
                                 gap_minutes=gap_minutes, limit=limit, since=since,
                                 until=until, level=level, team=team),
        default=str,
    )


@mcp.tool(description=(
    "A number over time, bucketed by hour | day | week. `days` counts back from the last timestamp "
    "in the data (2005 for BGL, 2017 for OpenStack), never from today. A role whose relation is "
    "bucketed daily cannot produce an hourly trend, and says so instead of substituting one."))
def trend(
    dataset: str,
    persona: str | None = None,
    bucket: str = "day",
    days: int | None = None,
    limit: int = 400,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> str:
    return json.dumps(
        analytics.trend(dataset=dataset, persona=persona, bucket=bucket, days=days, limit=limit,
                    since=since, until=until, level=level, team=team),
        default=str,
    )


@mcp.tool(description=(
    "OpenStack server lifecycle phases (spawn/build/image/boot/lifetime), worst first. The engineer "
    "and the lead get instances and can name the slow ones; the manager gets the percentile "
    "distribution, because that role's view deliberately carries no instance ids. The only place "
    "the four labelled anomalies in anomaly_labels.txt are visible at all."))
def durations(
    dataset: str = "openstack",
    persona: str | None = None,
    by: str = "spawn_s",
    limit: int = 20,
    team: str | None = None,
) -> str:
    return json.dumps(analytics.durations(dataset=dataset, persona=persona, by=by, limit=limit, team=team), default=str)


@mcp.tool(description=(
    "The team-ownership table (who owns which component, service or signature), and whether "
    "anything in the corpus is unowned -- checked against the data, not asserted. The manager has "
    "no grant on owner_map and receives a refusal: that role's views carry `team` on every row, so "
    "ownership arrives with the number."))
def ownership(
    persona: str | None = None,
    dataset: str | None = None,
    team: str | None = None,
    limit: int = 100,
) -> str:
    return json.dumps(analytics.ownership(persona=persona, dataset=dataset, team=team, limit=limit), default=str)


@mcp.tool(description=(
    "What else was happening within `minutes` either side of one log line -- anchor on id or on a "
    "timestamp. Engineer only: it walks the index relation line by line and the other roles have no "
    "grant on it. Returns the window's lines, the busiest signatures in it, and the id range."))
def nearby_events(
    dataset: str,
    persona: str | None = None,
    ts: str | None = None,
    id: int | None = None,
    minutes: int = 15,
    limit: int = 20,
) -> str:
    return json.dumps(analytics.nearby_events(dataset=dataset, persona=persona, ts=ts, id=id, minutes=minutes,
                            limit=limit), default=str)


@mcp.tool(description=(
    "What changed: the last window_hours against a baseline, per hour on both sides so a shorter "
    "window does not read as a decline, anchored to the last timestamp in the data. rate_ratio > 1 "
    "= arriving faster than baseline; is_new = absent from the baseline. Hours are read as whole "
    "days for roles whose views are daily."))
def what_changed(
    dataset: str,
    persona: str | None = None,
    window_hours: int = 6,
    baseline_hours: int = 24,
    min_lines: int = 1,
    limit: int = 20,
) -> str:
    return json.dumps(
        analytics.what_changed(dataset=dataset, persona=persona, window_hours=window_hours,
                           baseline_hours=baseline_hours, min_lines=min_lines, limit=limit),
        default=str,
    )


@mcp.tool(description=(
    "Re-run a stored answer and compare it, hash for hash. Every envelope prints an evidence id; "
    "pass it here to have the exact statement re-executed under the exact role with the exact "
    "parameters. A MISMATCH means the corpus or the definition moved since the answer was given."))
def verify_evidence(evidence_id: str, sample: int = 3) -> str:
    return json.dumps(analytics.verify_evidence(evidence_id=evidence_id, sample=sample), default=str)


@mcp.tool(description=(
    "Lint an answer before sending it. Two rules from the plan are enforced in code: a manager "
    "answer may not claim money, downtime, customers, revenue or an SLA (quoting them from a log "
    "line is allowed), and every figure in the Observed block must cite an evidence id that "
    "resolves; with deep=true each cited statement is re-run and its rows searched for the figures. "
    "Returns verdict ok / warnings / rejected with one row per finding. It never rewrites the "
    "answer, and it is not a data claim: no evidence id, nothing written to the ledger."))
def lint_answer(answer: str, persona: str | None = None, deep: bool = False) -> str:
    return json.dumps(lint.lint_answer(answer=answer, persona=persona or "", deep=deep), default=str)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
