#!/usr/bin/env python3
"""Minimal, dependency-free Markdown -> print-ready HTML -> PDF.

Written because this box has no pandoc and PEP 668 blocks a plain pip install. Handles
exactly the subset docs/process/PLAN.md uses: ATX headings, GFM pipe tables, fenced code, blockquotes,
bullet/ordered lists (one level of nesting), rules, bold/italic/inline-code, links, task
boxes. Anything else passes through as text, which is the safe failure.

    python3 scripts/md2pdf.py docs/process/PLAN.md PLAN.pdf
"""
from __future__ import annotations

import html
import re
import subprocess
import sys
import tempfile
from pathlib import Path

CHROME_CANDIDATES = [
    "chromium", "chromium-browser", "google-chrome", "google-chrome-stable",
    "/home/ubuntu/.local/bin/chromium",
]

CSS = """
@page { size: A4; margin: 16mm 14mm 18mm 14mm; }
* { box-sizing: border-box; }
body { font: 10.2pt/1.5 -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
       color: #14181f; margin: 0; }
h1 { font-size: 20pt; line-height: 1.2; margin: 0 0 2mm; letter-spacing: -0.2pt; }
h2 { font-size: 13.5pt; margin: 8mm 0 2.5mm; padding-bottom: 1.2mm;
     border-bottom: 1.5pt solid #14181f; page-break-after: avoid; }
h3 { font-size: 11.4pt; margin: 5.5mm 0 2mm; color: #1c2430; page-break-after: avoid; }
h4 { font-size: 10.4pt; margin: 4mm 0 1.5mm; color: #35404f; page-break-after: avoid; }
p, li { margin: 0 0 2mm; }
ul, ol { margin: 0 0 2.5mm; padding-left: 6mm; }
li > ul, li > ol { margin-top: 1.2mm; }
a { color: #0b57c4; text-decoration: none; word-break: break-word; }
code { font-family: "SF Mono", Menlo, Consolas, monospace; font-size: 8.9pt;
       background: #f1f3f6; padding: 0.4mm 1mm; border-radius: 1.5mm; }
pre { background: #f6f8fa; border: 0.6pt solid #d8dee6; border-left: 2.4pt solid #6b7785;
      border-radius: 1.5mm; padding: 2.6mm 3mm; margin: 0 0 3mm; overflow-x: auto;
      page-break-inside: avoid; }
pre code { background: none; padding: 0; font-size: 8.4pt; line-height: 1.42; }
table { border-collapse: collapse; width: 100%; margin: 0 0 3.5mm; font-size: 9.3pt;
        page-break-inside: avoid; }
th, td { border: 0.6pt solid #ccd4de; padding: 1.5mm 2mm; text-align: left;
         vertical-align: top; }
th { background: #eef1f5; font-weight: 600; }
td:first-child { white-space: nowrap; }
blockquote { margin: 0 0 3.5mm; padding: 1.8mm 0 1.8mm 4mm; border-left: 2.4pt solid #b9c2cd;
             background: #fafbfc; color: #35404f; }
blockquote p:last-child { margin-bottom: 0; }
hr { border: 0; border-top: 0.8pt solid #d8dee6; margin: 5mm 0; }
strong { font-weight: 650; }
.task { list-style: none; margin-left: -4mm; }
h2, h3 { break-after: avoid-page; }
"""


def inline(text: str) -> str:
    """Escape, then apply inline markup. Code spans are protected first."""
    spans: list[str] = []

    def stash(m: re.Match) -> str:
        spans.append(m.group(1))
        return f"\x00{len(spans) - 1}\x00"

    text = re.sub(r"`([^`]+)`", stash, text)
    text = html.escape(text, quote=False)
    # bold first, tolerant of inner *italics* (e.g. **works against *this* thing**)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    for i, raw in enumerate(spans):
        text = text.replace(f"\x00{i}\x00", f"<code>{html.escape(raw, quote=False)}</code>")
    return text


def is_table_row(line: str) -> bool:
    return line.startswith("|") and line.rstrip().endswith("|")


def is_sep_row(line: str) -> bool:
    return bool(re.fullmatch(r"\|[\s:|-]+\|", line.strip()))


def render_table(rows: list[str]) -> str:
    def cells(row: str) -> list[str]:
        return [c.strip() for c in row.strip().strip("|").split("|")]

    header = cells(rows[0])
    aligns = []
    for spec in cells(rows[1]):
        aligns.append("center" if spec.startswith(":") and spec.endswith(":")
                      else "right" if spec.endswith(":") else "left")
    out = ["<table>", "<thead><tr>"]
    for cell, align in zip(header, aligns):
        out.append(f'<th style="text-align:{align}">{inline(cell)}</th>')
    out.append("</tr></thead><tbody>")
    for row in rows[2:]:
        out.append("<tr>")
        for cell, align in zip(cells(row), aligns):
            out.append(f'<td style="text-align:{align}">{inline(cell)}</td>')
        out.append("</tr>")
    out.append("</tbody></table>")
    return "\n".join(out)


def convert(md: str) -> str:
    md = md.replace("\r\n", "\n").replace("≈", "&asymp;").replace("\x00", " ")
    lines = md.split("\n")
    html_out: list[str] = []
    i, n = 0, len(lines)

    while i < n:
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("```"):
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            html_out.append(f"<pre><code>{html.escape(chr(10).join(buf))}</code></pre>")
            continue

        if is_table_row(line) and i + 1 < n and is_sep_row(lines[i + 1]):
            rows = []
            while i < n and is_table_row(lines[i]):
                rows.append(lines[i])
                i += 1
            html_out.append(render_table(rows))
            continue

        if not stripped:
            i += 1
            continue

        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            lvl = len(m.group(1))
            html_out.append(f"<h{lvl}>{inline(m.group(2))}</h{lvl}>")
            i += 1
            continue

        if re.fullmatch(r"-{3,}|\*{3,}|_{3,}", stripped):
            html_out.append("<hr>")
            i += 1
            continue

        if stripped.startswith(">"):
            buf = []
            while i < n and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip()[1:].strip())
                i += 1
            inner = "".join(f"<p>{inline(b)}</p>" for b in buf if b)
            html_out.append(f"<blockquote>{inner}</blockquote>")
            continue

        m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", line)
        if m:
            ordered = m.group(2)[0].isdigit()
            tag = "ol" if ordered else "ul"
            items: list[str] = []
            while i < n:
                mm = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", lines[i])
                if not mm:
                    break
                body = mm.group(3)
                task = re.match(r"^\[([ xX])\]\s+(.*)$", body)
                if task:
                    mark = "☑" if task.group(1).lower() == "x" else "☐"
                    items.append(f'<li class="task">{mark} {inline(task.group(2))}</li>')
                else:
                    items.append(f"<li>{inline(body)}</li>")
                i += 1
            html_out.append(f"<{tag}>" + "".join(items) + f"</{tag}>")
            continue

        buf = [stripped]
        i += 1
        while i < n and lines[i].strip() and not re.match(
                r"^\s*(#{1,6}\s|[-*]\s|\d+\.\s|>|\||```)", lines[i]):
            buf.append(lines[i].strip())
            i += 1
        html_out.append("<p>" + inline(" ".join(buf)) + "</p>")

    title = next((re.sub(r"^#\s+", "", ln) for ln in lines if ln.startswith("# ")), "Document")
    return (f'<!doctype html><html><head><meta charset="utf-8">'
            f"<title>{html.escape(title)}</title><style>{CSS}</style></head>"
            f"<body>{chr(10).join(html_out)}</body></html>")


def find_chrome() -> str:
    for cand in CHROME_CANDIDATES:
        if Path(cand).exists() or subprocess.run(
                ["bash", "-lc", f"command -v {cand}"], capture_output=True).returncode == 0:
            return cand
    raise SystemExit("no chromium/chrome found")


def main() -> int:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, dest = Path(sys.argv[1]), Path(sys.argv[2])
    html_doc = convert(src.read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "page.html"
        page.write_text(html_doc, encoding="utf-8")
        cmd = [find_chrome(), "--headless=new", "--no-sandbox", "--disable-gpu",
               "--no-pdf-header-footer", "--virtual-time-budget=8000",
               f"--print-to-pdf={dest.resolve()}", page.as_uri()]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            print(res.stdout[-2000:], res.stderr[-2000:], file=sys.stderr)
            return res.returncode
    print(f"wrote {dest} ({dest.stat().st_size / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
