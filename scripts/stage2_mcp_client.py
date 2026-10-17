#!/usr/bin/env python3
"""Stock-client check: launch the MCP server over stdio and use it like a client would.

This is the acceptance test that matters -- it proves the MCP surface works, not just that the
Python functions do. Run: uv run python scripts/stage2_mcp_client.py
"""
from __future__ import annotations

import asyncio
import json
import pathlib
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

REPO = pathlib.Path(__file__).resolve().parent.parent


def payload(result) -> dict:
    """MCP results carry text content; our tools return one JSON document."""
    for item in getattr(result, "content", []) or []:
        text = getattr(item, "text", None)
        if text:
            return json.loads(text)
    if getattr(result, "structured_content", None):
        return result.structured_content
    raise SystemExit(f"no text content in result: {result!r}")


async def main() -> int:
    params = StdioServerParameters(
        command="uv",
        args=["run", "python", "-m", "exhibit.server"],
        cwd=str(REPO),
    )
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            info = init.server_info
            print(f"connected: {info.name} {getattr(info, 'version', '')}")

            listed = await session.list_tools()
            names = [t.name for t in listed.tools]
            print(f"tools: {', '.join(names)}")
            for expected in ("describe_data", "search_logs", "count_events"):
                assert expected in names, f"tool {expected} is missing"
            print("all three tools are exposed")

            print("\ncalling count_events(bgl, group_by=team)")
            res = payload(await session.call_tool("count_events", {"dataset": "bgl", "group_by": "team", "limit": 3}))
            print(" ", res["headline"])
            print(" ", "top buckets:", [(r["bucket"], r["n"]) for r in res["rows"]])

            print("\ncalling search_logs(bgl, 'data TLB error interrupt', phrase)")
            res = payload(await session.call_tool("search_logs", {
                "dataset": "bgl", "query": "data TLB error interrupt", "mode": "phrase", "limit": 1}))
            print(" ", res["headline"])
            print(" ", "operator:", res["operator"])
            print(" ", "first highlight:", (res["rows"][0]["highlight"] or "")[:120].replace("\n", " "))

            print("\ncalling describe_data")
            res = payload(await session.call_tool("describe_data", {"dataset": "openstack"}))
            print(" ", res["headline"])
            print(" ", "group options:", ", ".join(res["rows"][0]["group_by_options"]))

            print("\nstock-client check: PASS")
            return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
