#!/usr/bin/env python3
"""
mlController Dev Server
Serves the web dashboard with mock API for UI development/preview.
For production, build the Swift app: make bundle && make run
"""

import json
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse
import time

PORT = 8990
WEB_DIR = Path(__file__).parent / "Sources" / "mlController" / "Resources" / "web"

MOCK_STATUS = {
    "running": True,
    "openDocuments": [
        {"id": "doc1", "name": "Morning Show", "path": "/Users/demo/Documents/MorningShow.mls"},
        {"id": "doc2", "name": "Live Event 2024", "path": "/Users/demo/Documents/LiveEvent2024.mls"},
    ],
    "localDocuments": [
        "/Users/demo/Documents/MorningShow.mls",
        "/Users/demo/Documents/LiveEvent2024.mls",
        "/Users/demo/Documents/TestBroadcast.mls",
        "/Users/demo/Documents/ArchiveShow.mls",
    ]
}

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js":   "application/javascript",
    ".css":  "text/css",
    ".json": "application/json",
    ".png":  "image/png",
    ".ico":  "image/x-icon",
}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        ts = time.strftime("%H:%M:%S")
        print(f"  [{ts}] {fmt % args}")

    def send_json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(data))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path

        # API
        if path == "/api/status":
            self.send_json(200, MOCK_STATUS)
            return

        # Static files
        if path == "/":
            path = "/index.html"
        file_path = WEB_DIR / path.lstrip("/")
        if file_path.exists() and file_path.is_file():
            data = file_path.read_bytes()
            mime = MIME.get(file_path.suffix, "application/octet-stream")
            self.send_response(200)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", len(data))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b"{}"

        if path == "/api/start":
            MOCK_STATUS["running"] = True
            print("  [MOCK] mimoLive → starting")
            self.send_json(200, {"status": "starting"})
        elif path == "/api/stop":
            MOCK_STATUS["running"] = False
            MOCK_STATUS["openDocuments"] = []
            print("  [MOCK] mimoLive → stopping")
            self.send_json(200, {"status": "stopping"})
        elif path == "/api/restart":
            print("  [MOCK] mimoLive → restarting")
            self.send_json(200, {"status": "restarting"})
        elif path == "/api/open":
            try:
                data = json.loads(body)
                print(f"  [MOCK] Opening: {data.get('path', '?')}")
            except Exception:
                pass
            self.send_json(200, {"status": "opening"})
        else:
            self.send_json(404, {"error": "not found"})


if __name__ == "__main__":
    if not WEB_DIR.exists():
        print(f"Error: Web directory not found at {WEB_DIR}")
        sys.exit(1)

    print()
    print("  mlController Dev Server (Mock Mode)")
    print(f"  Dashboard → http://localhost:{PORT}")
    print(f"  Web files → {WEB_DIR}")
    print("  Press Ctrl+C to stop")
    print()

    server = HTTPServer(("0.0.0.0", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Stopped.")
