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
            expected = ("describe_data", "search_logs", "count_events", "episodes",
                        "top_signatures", "trend", "durations", "ownership", "nearby_events",
                        "what_changed", "verify_evidence")
            for name in expected:
                assert name in names, f"tool {name} is missing"
            print(f"all {len(expected)} tools are exposed")

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

            print("\nthe same question, asked as the three personas")
            for who in ("engineer", "lead", "manager"):
                res = payload(await session.call_tool("count_events", {
                    "dataset": "bgl", "group_by": "team", "persona": who, "limit": 2}))
                print(f"  {who:9s} {res['headline']}")
                if not res["refused"]:
                    print(f"            top: {[(r['bucket'], r['n']) for r in res['rows']]}")

            print("\nand the lead asking for log text")
            res = payload(await session.call_tool("search_logs", {
                "dataset": "bgl", "query": "ciod", "persona": "lead", "limit": 1}))
            print(" ", res["headline"])
            print(" ", res["notes"][0][:160])
            assert res["refused"] is True, "the lead must not be able to search"

            print("\nStage 3, through the same stock client: incidents, not lines")
            res = payload(await session.call_tool("episodes", {
                "dataset": "bgl", "gap_minutes": 5, "limit": 1}))
            print(" ", res["headline"])
            worst = res["rows"][0]
            print(f"    deepest incident: {worst['signature']} on {worst['midplane']} — "
                  f"{worst['lines']:,} lines, {worst['nodes']} node(s), {worst['span']}")
            assert res["total_matches"] == 19_250, f"expected 19,250 incidents, got {res['total_matches']}"
            assert worst["lines"] == 152_182 and worst["nodes"] == 1

            print("\nand the same question at an hour's gap, as the lead (whose relation is pre-grouped)")
            res2 = payload(await session.call_tool("episodes", {
                "dataset": "bgl", "gap_minutes": 60, "persona": "lead", "limit": 1}))
            print(" ", res2["headline"])
            print(" ", res2["notes"][0][:150])
            assert res2["refused"] is True

            print("\nre-running the first answer from the evidence ledger")
            ver = payload(await session.call_tool("verify_evidence", {"evidence_id": res["evidence_id"]}))
            print(f"  {ver['evidence_id']}: match={ver['match']} "
                  f"({ver['rows_recorded']:,} rows recorded, {ver['rows_now']:,} now)")
            print(f"  {ver['verdict']}")
            assert ver["match"] is True

            print("\nranked by blast radius instead of volume")
            res3 = payload(await session.call_tool("top_signatures", {
                "dataset": "bgl", "by": "nodes", "limit": 1}))
            top = res3["rows"][0]
            print(f"  {top['signature']} on {top['midplane']}: {top['nodes']} nodes, "
                  f"{top['lines']:,} lines, {top['episodes']} episodes")

            print("\nstock-client check: PASS")
            return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
