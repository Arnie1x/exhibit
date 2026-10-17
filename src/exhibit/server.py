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

from . import tools

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
  produced 49,154 across 22,529 nodes. The `episodes` tool answers that and arrives in Stage 3.
"""

mcp = MCPServer(
    name="exhibit",
    title="Logging off Early — log intelligence on SereneDB",
    instructions=INSTRUCTIONS,
    version="0.2.0",
)


@mcp.tool(description=(
    "What the given persona can ask, of which data, over what period, grouped how. Call this first. "
    "persona: engineer | lead | manager (default engineer)."))
def describe_data(dataset: str | None = None, persona: str | None = None) -> str:
    return json.dumps(tools.describe_data(persona, dataset), default=str)


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
        tools.search_logs(dataset, query, persona, mode, limit, since, until, level, team),
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
        tools.count_events(dataset, group_by, persona, query, mode, limit, since, until, level, team),
        default=str,
    )


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
