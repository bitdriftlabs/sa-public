#!/usr/bin/env python3
"""Tiny local collector for the RN and Flutter test harness (stdlib only).

The apps can't write files from JS/Dart without a plugin and can't take launch arguments
without native code, so in debug builds they talk to this server instead:
  GET  /config  -> {"runs": N, "seed": S, "persona": "..."}  (the app autoruns when it gets this)
  POST /record  -> body is one JSON record per line, appended to --out
The server exits shortly after it has seen a `sim_autorun_complete` record, or after --timeout.

Usage: collector.py --out FILE --runs N [--seed S] [--persona P] [--port 5599] [--timeout 600]
"""
import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--runs", type=int, required=True)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--persona", default="control")
    ap.add_argument("--port", type=int, default=5599)
    ap.add_argument("--timeout", type=int, default=600)
    a = ap.parse_args()

    state = {"served": 0, "done": False, "lines": 0}
    lock = threading.Lock()
    out = open(a.out, "w")

    class H(BaseHTTPRequestHandler):
        def log_message(self, *args):  # quiet
            pass

        def _send(self, code, body=b"{}"):
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path.startswith("/config"):
                with lock:
                    state["served"] += 1
                self._send(200, json.dumps({"runs": a.runs, "seed": a.seed, "persona": a.persona}).encode())
            elif self.path.startswith("/status"):
                with lock:
                    self._send(200, json.dumps(state).encode())
            else:
                self._send(404)

        def do_POST(self):
            if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
                chunks = []
                while True:
                    size = int(self.rfile.readline().strip() or b"0", 16)
                    if size == 0:
                        self.rfile.readline()
                        break
                    chunks.append(self.rfile.read(size))
                    self.rfile.readline()
                body = b"".join(chunks).decode("utf-8", "replace")
            else:
                n = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(n).decode("utf-8", "replace")
            with lock:
                for line in body.splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    out.write(line + "\n")
                    state["lines"] += 1
                    if '"sim_autorun_complete"' in line:
                        state["done"] = True
                out.flush()
            self._send(200)

    srv = HTTPServer(("0.0.0.0", a.port), H)
    srv.timeout = 0.5
    deadline = time.time() + a.timeout
    done_at = None
    while time.time() < deadline:
        srv.handle_request()
        with lock:
            if state["done"] and done_at is None:
                done_at = time.time() + 1.5  # let trailing records arrive
        if done_at and time.time() >= done_at:
            break
    out.close()
    with lock:
        ok = state["done"]
    print("collector: %s (config served %d times, %d lines)" % ("complete" if ok else "TIMED OUT", state["served"], state["lines"]))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
