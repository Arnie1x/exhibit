"""MCP server exposing the Stage 2 tools over stdio.

Run it:  uv run exhibit-mcp        (or: make mcp)
Point a client at it: any MCP client speaking stdio. `scripts/stage2_mcp_client.py` is a
stock-client check that lists the tools and makes one real call.

Note for MCP 2.x: the class is MCPServer (FastMCP was renamed). ``mcp`` 1.x used
``from mcp.server.fastmcp import FastMCP``; this project is on the 2.x API.
"""
from __future__ import annotations

import json

from mcp.server.mcpserver import MCPServer

from . import tools

INSTRUCTIONS = """Log intelligence over BGL and OpenStack log corpora, computed in SereneDB.

Every answer comes back as an envelope carrying the rows, the SQL, the bound parameters, the true
match total, whether it was truncated, and an evidence id. Quote the evidence id.

Rules the server enforces, so do not fight them:
* numbers come from SQL, never from you -- never compute or estimate a figure yourself;
* search runs against an inverted-indexed relation, aggregation against the base table;
* the operator that produced a count is stated in every envelope (term / phrase / any / all);
* `count_events` counts LINES. Lines are not incidents (one node produced 136,209 lines in six
  hours while a fleet-wide event produced 49,154 across 22,529 nodes) -- the `episodes` tool is the
  incident-level answer and arrives in Stage 3.
"""

mcp = MCPServer(
    name="exhibit",
    title="Logging off Early — log intelligence on SereneDB",
    instructions=INSTRUCTIONS,
    version="0.1.0",
)


@mcp.tool(description="List the available datasets with their row counts, time range, grouping options, ownership and scope notes. Call this first.")
def describe_data(dataset: str | None = None) -> str:
    return json.dumps(tools.describe_data(dataset), default=str)


@mcp.tool(description=(
    "Full-text search over one dataset's logs. Returns matching lines with highlighted terms, "
    "plus the true total match count and an evidence id. mode: term | phrase | any | all "
    "(default phrase; `any`/`all` take a comma-separated list)."))
def search_logs(
    dataset: str,
    query: str,
    mode: str = "phrase",
    limit: int = 10,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> str:
    return json.dumps(
        tools.search_logs(dataset, query, mode, limit, since, until, level, team), default=str
    )


@mcp.tool(description=(
    "Count log lines bucketed by a column (signature, component, level, team, node, ...). Omit "
    "`query` for pure aggregation; pass it to count matches of a full-text predicate instead. "
    "Returns the grand total and whether the bucket list was truncated."))
def count_events(
    dataset: str,
    group_by: str = "signature",
    query: str | None = None,
    mode: str = "phrase",
    limit: int = 20,
    since: str | None = None,
    until: str | None = None,
    level: str | None = None,
    team: str | None = None,
) -> str:
    return json.dumps(
        tools.count_events(dataset, group_by, query, mode, limit, since, until, level, team),
        default=str,
    )


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
