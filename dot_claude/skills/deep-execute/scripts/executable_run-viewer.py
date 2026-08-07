#!/usr/bin/env python3
"""Live, read-only viewer for /deep-execute runs.

A lens, never a control plane. `events.jsonl` and `manifest.json` inside a run
directory stay the single source of truth; this process only reads them. It
never writes into a run directory, never spawns anything, and never contacts a
model. If it is down, runs are unaffected — that is the whole point of the
design, and any change that weakens it is a change to the wrong thing.

Interpreter note: the LaunchAgent invokes /usr/bin/python3 by absolute path,
because launchd's PATH picks up mise shims and Homebrew and both move. That
interpreter is 3.9 on macOS 26, while PATH python3 here is 3.12. So this file
must stay 3.9-compatible: no `match`, no runtime PEP 604 unions. The test
suite parses it under /usr/bin/python3 specifically for that reason.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# The five keys event.sh writes, and the eight types it accepts. Kept in sync
# with schemas/run-state.schema.json by hand; a line failing this becomes an
# invalid_event rather than taking the endpoint down, which is the stance
# monitor-events.sh already takes.
EVENT_KEYS = ("ts", "lane", "task", "type", "msg")
EVENT_TYPES = frozenset(
    (
        "task_start",
        "task_done",
        "progress",
        "question",
        "waiting",
        "blocked",
        "done",
        "decision",
    )
)

RUN_ID_RE = re.compile(r"[A-Za-z0-9._-]{1,128}")

# Timeline cap. The real run on disk holds 42 events; this is insurance against
# a long run, not a projection. The lane-status fold below is streaming and
# unaffected by it.
MAX_TIMELINE = 2000

# Per-decision read cap, so one oversized record cannot balloon a response.
MAX_DECISION_BYTES = 262144


def resolve_run_dir(runs_dir, run_id):
    """Return the absolute run directory, or None when it is not a real run.

    This is a trust boundary: run_id arrives from the URL. Shape first, then a
    realpath containment check, so neither a traversal sequence nor a symlink
    pointing out of runs_dir can escape.
    """
    if run_id in (".", "..") or not RUN_ID_RE.fullmatch(run_id):
        return None
    root = os.path.realpath(runs_dir)
    candidate = os.path.realpath(os.path.join(root, run_id))
    if candidate != root and not candidate.startswith(root + os.sep):
        return None
    if not os.path.isfile(os.path.join(candidate, "manifest.json")):
        return None
    return candidate


def parse_event(raw):
    """Turn one events.jsonl line into an event dict.

    Anything that is not a well-formed event of a known type becomes an
    `invalid_event` carrying the offending text, rather than being dropped or
    raising. Unknown EXTRA keys are deliberately preserved: the schema forbids
    them today, but when --mode and --topic land the API already carries them
    and only the rendering changes.
    """
    text = raw.decode("utf-8", "replace").strip()
    if not text:
        return None
    try:
        obj = json.loads(text)
    except ValueError:
        return _invalid(text)
    if not isinstance(obj, dict):
        return _invalid(text)
    for key in EVENT_KEYS:
        if key not in obj or not isinstance(obj[key], str):
            return _invalid(text)
    if obj["type"] not in EVENT_TYPES:
        return _invalid(text)
    return obj


def _invalid(text):
    return {
        "ts": "",
        "lane": "",
        "task": "",
        "type": "invalid_event",
        "msg": text[:200],
    }


def read_events(events_path):
    """Read every event, plus the streaming lane-status fold.

    board.sh:56-64 groups by [lane, task], sorts each group by ts and takes the
    last; build-run-report.sh:462-464 already duplicates that jq verbatim, so
    duplicating the fold here is the established precedent in this repo rather
    than a new one.

    `ts` is second-precision, so same-second events tie, and jq's stable
    sort_by breaks ties by input order. Iterating the file forward and
    replacing on `>=` reproduces that exactly. Collecting into a dict and
    sorting afterwards, or walking the file backwards, diverges silently.
    """
    events = []
    latest = {}
    total = 0
    try:
        with open(events_path, "rb") as handle:
            for raw in handle:
                if not raw.endswith(b"\n"):
                    # A writer mid-append. event.sh appends a sub-4096-byte line
                    # with a single >>, so this is rare, but a torn final line
                    # must never be parsed as a whole one.
                    break
                event = parse_event(raw)
                if event is None:
                    continue
                total += 1
                events.append(event)
                if len(events) > MAX_TIMELINE:
                    events.pop(0)
                key = (event["lane"], event["task"])
                previous = latest.get(key)
                if previous is None or event["ts"] >= previous["ts"]:
                    latest[key] = event
    except FileNotFoundError:
        # A run scaffolded but not yet started. board.sh:50-53 treats this the
        # same way — an empty board, not an error.
        return [], [], 0, False

    lane_status = [
        {
            "lane": event["lane"],
            "task": event["task"],
            "status": event["type"],
            "msg": event["msg"],
            "ts": event["ts"],
        }
        for _, event in sorted(latest.items(), key=lambda item: item[0])
    ]
    return events, lane_status, total, True


def read_decisions(run_dir):
    """Every decision record a lane wrote, oldest id first.

    Absence here is meaningful and must not be dressed up: a decision no lane
    recorded through decision.sh simply is not in the run directory.
    """
    records = []
    lanes_dir = os.path.join(run_dir, "lanes")
    if not os.path.isdir(lanes_dir):
        return records
    for lane in sorted(os.listdir(lanes_dir)):
        decisions_dir = os.path.join(lanes_dir, lane, "decisions")
        if not os.path.isdir(decisions_dir):
            continue
        for name in sorted(os.listdir(decisions_dir)):
            if not name.endswith(".json"):
                continue
            path = os.path.join(decisions_dir, name)
            try:
                with open(path, "rb") as handle:
                    record = json.loads(handle.read(MAX_DECISION_BYTES))
            except (OSError, ValueError):
                continue
            if isinstance(record, dict):
                records.append(record)
    return records


def build_snapshot(run_dir):
    """Assemble everything the page needs in one read."""
    with open(os.path.join(run_dir, "manifest.json"), "rb") as handle:
        manifest = json.load(handle)

    events, lane_status, total, present = read_events(
        os.path.join(run_dir, "events.jsonl")
    )

    # workers[].status is written as "pending" at init and no script in the
    # skill ever updates it. Surfacing it would be a lie on a live page, so the
    # lane list drops it and status comes from the event fold alone.
    lanes = [
        {
            "lane": worker.get("lane", ""),
            "task": worker.get("task", ""),
            "runner": worker.get("runner", ""),
            "effort": worker.get("effort", ""),
        }
        for worker in manifest.get("workers", [])
    ]

    report = os.path.join(run_dir, "report", "index.html")
    return {
        "run_id": manifest.get("run_id", os.path.basename(run_dir)),
        "round": manifest.get("round"),
        "max_rounds": manifest.get("max_rounds"),
        "baseline_commit": manifest.get("baseline_commit", ""),
        "plan_path": manifest.get("plan_path", ""),
        "cwd": manifest.get("cwd", ""),
        "contract": manifest.get("contract", {}),
        "shared_read_only": manifest.get("shared_read_only", []),
        "lanes": lanes,
        "lane_status": lane_status,
        "events": events,
        "total_events": total,
        "truncated": total > len(events),
        "decisions": read_decisions(run_dir),
        "events_file_present": present,
        "report_available": os.path.isfile(report),
    }


def list_runs(runs_dir):
    """Every directory under runs_dir holding a manifest.json, newest first."""
    runs = []
    try:
        entries = os.listdir(runs_dir)
    except OSError:
        return runs
    for name in entries:
        run_dir = resolve_run_dir(runs_dir, name)
        if run_dir is None:
            continue
        events_path = os.path.join(run_dir, "events.jsonl")
        try:
            mtime = os.stat(events_path).st_mtime
        except OSError:
            mtime = os.stat(os.path.join(run_dir, "manifest.json")).st_mtime
        runs.append({"run_id": name, "mtime": mtime})
    runs.sort(key=lambda run: run["mtime"], reverse=True)
    return runs


class Handler(BaseHTTPRequestHandler):
    # HTTP/1.1 for keep-alive; every response below therefore sets an accurate
    # Content-Length.
    protocol_version = "HTTP/1.1"
    server_version = "deep-execute-viewer"

    runs_dir = ""

    def do_GET(self):  # noqa: N802 - name fixed by BaseHTTPRequestHandler
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            self._send(200, "text/plain; charset=utf-8", b"ok\n")
            return
        api = re.fullmatch(r"/api/run/([^/]+)", path)
        if api:
            self._serve_snapshot(api.group(1))
            return
        self._send(404, "text/plain; charset=utf-8", b"not found\n")

    def _serve_snapshot(self, raw_run_id):
        run_dir = resolve_run_dir(self.runs_dir, raw_run_id)
        if run_dir is None:
            self._send_json(404, {"error": "unknown run"})
            return
        try:
            snapshot = build_snapshot(run_dir)
        except (OSError, ValueError) as exc:
            self._send_json(500, {"error": "unreadable run: %s" % exc})
            return
        self._send_json(200, snapshot)

    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self._send(status, "application/json; charset=utf-8", body)

    def _send(self, status, content_type, body):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, fmt, *args):
        # One compact line per request on stderr, which the LaunchAgent points
        # at a real file. /healthz is dropped because launchd and the test
        # suite poll it and it would drown everything else.
        if self.path.startswith("/healthz"):
            return
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--runs-dir",
        default=os.path.expanduser("~/.claude/deep-execute-runs"),
        help="directory holding run directories",
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument(
        "--port",
        type=int,
        default=41777,
        help="0 binds an ephemeral port; the bound URL is printed on stdout",
    )
    args = parser.parse_args(argv)

    Handler.runs_dir = os.path.expanduser(args.runs_dir)

    try:
        httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    except OSError as exc:
        # launchd retries forever under KeepAlive, so a taken port is visible
        # without help from us. One readable line beats a traceback in the log.
        sys.stderr.write("cannot bind %s:%d — %s\n" % (args.host, args.port, exc))
        return 1
    httpd.daemon_threads = True

    # Printed and flushed so the test suite can wait on the real bound port
    # instead of sleeping, which is what makes --port 0 usable there.
    print("http://%s:%d" % httpd.server_address[:2], flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
