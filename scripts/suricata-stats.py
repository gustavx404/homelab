#!/usr/bin/env python3
"""Suricata eve.json stats HTTP endpoint for the Homepage dashboard.

Serves aggregated counters (uptime, packets, drops, alerts, http, dns, tls)
by incrementally tailing Suricata's eve.json. Stdlib only, read-only on the log.
"""

import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EVE_JSON_PATH = os.environ.get("EVE_JSON_PATH", "/data/eve.json")
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8899"))

# event_type -> counter key
EVENT_COUNTERS = {"alert": "alerts", "http": "http", "dns": "dns", "tls": "tls"}


def format_uptime(seconds: int) -> str:
    if seconds <= 0:
        return "0s"
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes = rem // 60
    parts = []
    if days:
        parts.append(f"{days}d")
    if hours:
        parts.append(f"{hours}h")
    if minutes or not parts:
        parts.append(f"{minutes}m")
    return " ".join(parts)


class SuricataStats:
    """Incremental tail reader + aggregator for eve.json."""

    def __init__(self, path: str):
        self.path = path
        self.offset = 0
        self.uptime = 0
        self.packets = 0
        self.drops = 0
        self.counters = {"alerts": 0, "http": 0, "dns": 0, "tls": 0}
        self.lock = threading.Lock()

    def _read_new_lines(self) -> list[str]:
        try:
            size = os.path.getsize(self.path)
        except OSError:
            return []
        if self.offset > size:
            self.offset = 0  # log rotated/truncated: restart from the beginning
        if self.offset == size:
            return []
        try:
            with open(self.path, "rb") as fh:
                fh.seek(self.offset)
                data = fh.read()
                self.offset = fh.tell()
        except OSError:
            return []
        return data.decode("utf-8", errors="replace").splitlines()

    def update(self) -> None:
        with self.lock:
            for line in self._read_new_lines():
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue  # partial line while Suricata is writing
                event_type = event.get("event_type")
                if event_type == "stats":
                    stats = event.get("stats") or {}
                    self.uptime = int(stats.get("uptime", 0) or 0)
                    capture = stats.get("capture") or {}
                    self.packets = int(capture.get("kernel_packets", 0) or 0)
                    self.drops = int(capture.get("kernel_drops", 0) or 0)
                elif event_type in EVENT_COUNTERS:
                    self.counters[EVENT_COUNTERS[event_type]] += 1

    def snapshot(self) -> dict:
        with self.lock:
            return {
                "uptime": format_uptime(self.uptime),
                "packets": self.packets,
                "drops": self.drops,
                "alerts": self.counters["alerts"],
                "http": self.counters["http"],
                "dns": self.counters["dns"],
                "tls": self.counters["tls"],
            }


STATS = SuricataStats(EVE_JSON_PATH)


class StatsHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        STATS.update()
        if self.path == "/stats":
            self._send_json(200, STATS.snapshot())
        elif self.path == "/health":
            self._send_json(200, {"ok": True})
        else:
            self._send_json(404, {"error": "not found"})

    def _send_json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass  # keep the request log quiet


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), StatsHandler)
    print(f"suricata-stats listening on {HOST}:{PORT} (eve.json: {EVE_JSON_PATH})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
