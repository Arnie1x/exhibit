#!/usr/bin/env python3
"""Parse Loghub BGL + OpenStack into Parquet for SereneDB.

Run (needs pyarrow; `make parse` does exactly this):

  uv run --no-project --with pyarrow python -X utf8 scripts/parse.py --in data/loghub --out data/loghub

-X utf8 matters on Windows: without it open() decodes with the ANSI code page, not UTF-8, and
the 8 BGL lines that carry non-ASCII bytes come out differently from a Linux parse.
Without --in/--out both default to this script's folder.

Outputs in --out:
  bgl.parquet        one row per BGL log line (4.7M)
  openstack.parquet  one row per OpenStack log line (207,820)

WHY THIS IS NOT A SIMPLE WHITESPACE SPLIT
-----------------------------------------
BGL is published with three different record shapes in the same file. A naive
"split on whitespace, take field 9 as the level" parse silently loses 0.7% of the corpus
and mis-assigns component/level on another 2%:

  1. Well-formed (4.64M lines):
       - 1117838570 2005.06.03 R02-M1-N0-C:J12-U11 2005-06-03-15.42.50.363779 <node> RAS KERNEL INFO <message>
  2. Empty message, only 9 fields (34,470 lines):
       - 1120866514 2005.07.08 R02-M1-N8-C:J13-U01 2005-07-08-16.48.34.004234 <node> RAS KERNEL FATAL
  3. The type field is NULL, not RAS (100,141 lines -> DISCOVERY/HARDWARE/MONITOR/CMCS/SERV_NET):
       - 1118241709 2005.06.08 R33-M1-ND 2005-06-08-07.41.49.839299 R33-M1-ND NULL HARDWARE WARNING PrepareForService ...
  4. Multi-line entries that put message text BEFORE the triple, shifting every later field:
       - 1133447861 2005.12.01 - 2005-12-01-06.37.41.417709 time for a single instance ... RAS KERNEL INFO 0 microseconds ...

So: locate a "<TYPE> <COMPONENT> <LEVEL>" triple, where TYPE is RAS or NULL and LEVEL is one of
the seven levels the corpus actually uses. Prefer the positional match (field 7); fall back to
searching the token list. Any text found before the triple is folded back into the message.

Counting matters here: the brief asks for accurate counts and warns against treating matching
lines as separate incidents, so a parser that quietly drops 0.7% of rows is a scoring risk.
"""
import argparse
import os
import re
import sys

import pyarrow as pa
import pyarrow.parquet as pq

HERE = os.path.dirname(os.path.abspath(__file__))

LOG_TYPES = {"RAS", "NULL"}
LOG_LEVELS = {"INFO", "FATAL", "ERROR", "WARNING", "SEVERE", "FAILURE", "Kill"}

# BGL head: label, epoch, date, node, time, then the rest (repeat node + type/component/level + message).
BGL_HEAD_RE = re.compile(
    r"^(?P<label>\S+)\s+(?P<epoch>\d+)\s+(?P<date>\S+)\s+(?P<node>\S+)\s+(?P<time>\S+)\s+(?P<rest>.*)$"
)

# OpenStack: <file> <date> <time> <pid> <LEVEL> <logger> [<context>] <message...>
# The context bracket is OPTIONAL: 184 nova-compute lines (traceback headers) have no [req-...].
OS_RE = re.compile(
    r"^(?P<source>\S+)\s+(?P<date>\d{4}-\d{2}-\d{2})\s+(?P<time>\d{2}:\d{2}:\d{2}\.\d+)\s+"
    r"(?P<pid>\d+)\s+(?P<level>\S+)\s+(?P<logger>\S+)\s+(?:\[(?P<context>.*?)\])?\s*(?P<message>.*)$"
)
OS_STATUS_RE = re.compile(r"\bstatus:\s*(\d{3})")
OS_LATENCY_RE = re.compile(r"\btime:\s*([0-9.]+)")
OS_INSTANCE_RE = re.compile(r"\[instance:\s*([0-9a-fA-F-]{36})\]")

BGL_TS_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-(\d{2})\.(\d{2})\.(\d{2})\.(\d+)$")
UUID32 = re.compile(r"[0-9a-fA-F]{32}")
UUID36 = re.compile(r"[0-9a-fA-F-]{36}")


def bgl_timestamp(time_field: str) -> str | None:
    """2005-06-03-15.42.50.363779 -> '2005-06-03 15:42:50.363779'."""
    m = BGL_TS_RE.match(time_field)
    if not m:
        return None
    d, hh, mm, ss, frac = m.groups()
    return f"{d} {hh}:{mm}:{ss}.{frac}"


def split_bgl_rest(rest: str):
    """Return (node_repeat, log_type, component, level, content) for a BGL record tail."""
    tokens = rest.split()
    # Positional: <node_repeat> <TYPE> <component> <LEVEL> <message...>
    if len(tokens) >= 4 and tokens[1] in LOG_TYPES and tokens[3] in LOG_LEVELS:
        return tokens[0], tokens[1], tokens[2], tokens[3], " ".join(tokens[4:])
    # Tolerant: find the triple anywhere, fold surrounding text into the message.
    for i in range(len(tokens) - 2):
        if tokens[i] in LOG_TYPES and tokens[i + 2] in LOG_LEVELS:
            node_repeat = tokens[0] if i > 0 else ""
            content = " ".join(tokens[:i] + tokens[i + 3:]).strip()
            return node_repeat, tokens[i], tokens[i + 1], tokens[i + 2], content
    # No triple at all: keep the line, flag it with empty component/level rather than dropping it.
    return "", "", "", "", rest.strip()


def parse_bgl(path: str):
    cols = {k: [] for k in ("dataset", "label", "epoch", "date", "node", "ts_text",
                            "node_repeat", "log_type", "component", "level", "content")}
    bad = no_anchor = 0
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            m = BGL_HEAD_RE.match(line.rstrip("\n"))
            if not m:
                bad += 1
                continue
            g = m.groupdict()
            node_repeat, log_type, component, level, content = split_bgl_rest(g["rest"])
            if not log_type:
                no_anchor += 1
            cols["dataset"].append("BGL")
            cols["label"].append(g["label"])
            cols["epoch"].append(int(g["epoch"]))
            cols["date"].append(g["date"])
            cols["node"].append(g["node"])
            cols["ts_text"].append(bgl_timestamp(g["time"]) or "")
            cols["node_repeat"].append(node_repeat)
            cols["log_type"].append(log_type)
            cols["component"].append(component)
            cols["level"].append(level)
            cols["content"].append(content)
    print(f"BGL: {len(cols['dataset']):,} rows parsed, {bad:,} unusable, "
          f"{no_anchor:,} without a type/component/level triple")
    return cols


def parse_openstack(paths):
    cols = {k: [] for k in ("dataset", "origin_file", "source", "service", "ts_text", "pid", "level",
                            "logger", "request_id", "user_id", "tenant_id", "instance_id",
                            "status_code", "latency_s", "is_abnormal_file", "message")}
    bad = blank = 0
    for path in paths:
        name = os.path.basename(path)
        abnormal = "abnormal" in name
        with open(path, "r", errors="replace") as fh:
            for line in fh:
                raw = line.rstrip("\n").rstrip("\r")
                if not raw.strip():
                    blank += 1
                    continue
                m = OS_RE.match(raw)
                if not m:
                    bad += 1
                    continue
                g = m.groupdict()
                ctx = (g["context"] or "").split()
                req = next((t[4:] for t in ctx if t.startswith("req-")), "")
                # context is req-<id> <user_id> <tenant_id> - - - ; positions vary by service
                uuids = [t.strip("-") for t in ctx[1:]
                         if UUID32.fullmatch(t.strip("-")) or UUID36.fullmatch(t.strip("-"))]
                inst = OS_INSTANCE_RE.search(g["message"])
                st = OS_STATUS_RE.search(g["message"])
                lat = OS_LATENCY_RE.search(g["message"])

                cols["dataset"].append("OpenStack")
                cols["origin_file"].append(name)
                cols["source"].append(g["source"])
                cols["service"].append(g["source"].split(".")[0])
                cols["ts_text"].append(f"{g['date']} {g['time']}")
                cols["pid"].append(int(g["pid"]))
                cols["level"].append(g["level"])
                cols["logger"].append(g["logger"])
                cols["request_id"].append(req)
                cols["user_id"].append(uuids[0] if len(uuids) > 0 else "")
                cols["tenant_id"].append(uuids[1] if len(uuids) > 1 else "")
                cols["instance_id"].append(inst.group(1) if inst else "")
                cols["status_code"].append(int(st.group(1)) if st else None)
                cols["latency_s"].append(float(lat.group(1)) if lat else None)
                cols["is_abnormal_file"].append(abnormal)
                cols["message"].append(g["message"])
    print(f"OpenStack: {len(cols['dataset']):,} rows parsed, {bad:,} unusable, "
          f"{blank:,} blank lines skipped")
    return cols


def write_parquet(cols, out_path, schema):
    table = pa.table({k: pa.array(v, type=schema.field(k).type) for k, v in cols.items()},
                     schema=schema)
    pq.write_table(table, out_path, compression="zstd")
    print(f"wrote {out_path}: {table.num_rows:,} rows, {os.path.getsize(out_path) / 1e6:.1f} MB")


def main():
    # --in/--out as the Makefile passes them; both default to this script's folder (the old
    # in-container usage above).
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--in", dest="src", default=HERE, help="folder holding BGL.log and openstack_*.log")
    ap.add_argument("--out", dest="dst", default=HERE, help="folder for bgl.parquet and openstack.parquet")
    args = ap.parse_args()

    bgl_path = os.path.join(args.src, "BGL.log")
    os_paths = [os.path.join(args.src, n) for n in
                ("openstack_normal1.log", "openstack_normal2.log", "openstack_abnormal.log")]
    for p in [bgl_path, *os_paths]:
        if not os.path.exists(p):
            sys.exit(f"missing input: {p}")

    bgl = parse_bgl(bgl_path)
    bgl["timestamp"] = pa.array(bgl.pop("ts_text"), type=pa.string())
    bgl_schema = pa.schema([
        ("dataset", pa.string()), ("label", pa.string()), ("epoch", pa.int64()),
        ("date", pa.string()), ("node", pa.string()), ("timestamp", pa.string()),
        ("node_repeat", pa.string()), ("log_type", pa.string()), ("component", pa.string()),
        ("level", pa.string()), ("content", pa.string()),
    ])
    write_parquet(bgl, os.path.join(args.dst, "bgl.parquet"), bgl_schema)

    os_cols = parse_openstack(os_paths)
    os_cols["timestamp"] = pa.array(os_cols.pop("ts_text"), type=pa.string())
    os_schema = pa.schema([
        ("dataset", pa.string()), ("origin_file", pa.string()), ("source", pa.string()),
        ("service", pa.string()),
        ("timestamp", pa.string()), ("pid", pa.int64()), ("level", pa.string()),
        ("logger", pa.string()), ("request_id", pa.string()), ("user_id", pa.string()),
        ("tenant_id", pa.string()), ("instance_id", pa.string()),
        ("status_code", pa.int32()), ("latency_s", pa.float64()),
        ("is_abnormal_file", pa.bool_()), ("message", pa.string()),
    ])
    write_parquet(os_cols, os.path.join(args.dst, "openstack.parquet"), os_schema)


if __name__ == "__main__":
    main()
