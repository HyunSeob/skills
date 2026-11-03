#!/usr/bin/env python3
"""Template: expose native AX helper actions as MCP tools.

Replace MYAPP / BUNDLE_ID and the confirm logic with what ax_dump showed for your app.
Requires `pip install "mcp>=1.30,<2"`. Run with: python3 mcp_server.py
"""

import hashlib
import json
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations

from operation_journal import OperationJournal

BUNDLE_ID = "com.example.MyApp"  # TODO
HERE = Path(__file__).resolve().parent
SOURCE = HERE / "helper_action.swift"
CACHE = Path.home() / "Library/Caches/myapp-ax"
JOURNAL = OperationJournal(Path.home() / ".config/myapp-ax/operations")

mcp = FastMCP("myapp-ax", instructions=(
    "MYAPP is automated only through these myapp_ax_* tools. Do not replace them with screenshots, OCR or "
    "coordinate clicks. Reads return only what the app currently exposes. For myapp_ax_press pick one "
    "operation_id per user request; on outcome_unknown or a timeout call myapp_ax_result with the same ID "
    "and never retry with a new ID."
))
READ = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True, openWorldHint=False)
UI = ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=True, openWorldHint=True)
IRREVERSIBLE = ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=False, openWorldHint=True)


def binary():
    # Compile once per source hash so edits rebuild automatically.
    source = SOURCE.read_bytes()
    target = CACHE / ("helper-" + hashlib.sha256(source).hexdigest()[:16])
    if not target.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        subprocess.run(["swiftc", "-O", str(SOURCE), "-o", str(target)], check=True, capture_output=True)
    return target


def bridge(request, timeout=15):
    # User text goes through stdin JSON, never argv.
    completed = subprocess.run([str(binary())], input=json.dumps({"bundleId": BUNDLE_ID, **request}),
                               capture_output=True, text=True, timeout=timeout)
    return json.loads(completed.stdout)


def output(value):
    return json.dumps(value, ensure_ascii=False, indent=2)


@mcp.tool(annotations=READ)
def myapp_ax_inspect(window_title: str) -> str:
    """Check that the exact window is open, has no modal or draft, and the target button is unique.

    Changes nothing in the app.
    """
    return output(bridge({"windowTitle": window_title, "action": "inspect"}))


@mcp.tool(annotations=UI)
def myapp_ax_search(window_title: str, query: str) -> str:
    """Type a query into the window's search field (focus, select all, replace, confirm, wait).

    Results are what the app exposes after the debounce, not a full index.
    """
    return output(bridge({"windowTitle": window_title, "action": "search", "query": query}))


def confirm_factory(window_title):
    def confirm(baseline):
        # TODO: read the UI again and return True only when the expected change is visible,
        # e.g. one more message row whose text hash matches and an empty composer.
        state = bridge({"windowTitle": window_title, "action": "inspect"})
        return state.get("status") == "ready" and baseline is not None
    return confirm


@mcp.tool(annotations=IRREVERSIBLE)
def myapp_ax_press(window_title: str, operation_id: str) -> str:
    """Press the target button once, only when the user explicitly asked for it.

    operation_id: 1..128 of [A-Za-z0-9_.:-], chosen once per request. Reusing it returns the recorded
    result without pressing again. "observed" means the expected change was seen in the UI; it is not a
    server acknowledgement. On "outcome_unknown" call myapp_ax_result with the same ID; do not retry.
    """
    return output(JOURNAL.run(
        operation_id, {"window": window_title, "action": "press"},
        baseline=lambda: bridge({"windowTitle": window_title, "action": "inspect"}).get("status"),
        dispatch=lambda: bridge({"windowTitle": window_title, "action": "press"}),
        confirm=confirm_factory(window_title),
    ))


@mcp.tool(annotations=READ)
def myapp_ax_result(operation_id: str, window_title: str, wait_seconds: float = 0) -> str:
    """Look up an earlier myapp_ax_press by its operation_id. Never presses."""
    return output(JOURNAL.result(operation_id, confirm_factory(window_title), wait_seconds))


if __name__ == "__main__":
    mcp.run()
