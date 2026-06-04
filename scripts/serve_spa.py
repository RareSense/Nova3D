#!/usr/bin/env python3
"""Serve a Flutter web build with SPA route fallback."""

from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class SpaRequestHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        if self.path.split("?", 1)[0] == "/__reset":
            body = b"""<!doctype html>
<html>
<head><meta charset="utf-8"><title>Nova3D Reset</title></head>
<body style="background:#0f0f0f;color:#e5e7eb;font-family:system-ui,sans-serif">
<script>
(async function () {
  try {
    if ('serviceWorker' in navigator) {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.map(registration => registration.unregister()));
    }
    if ('caches' in window) {
      const names = await caches.keys();
      await Promise.all(names.map(name => caches.delete(name)));
    }
    try { localStorage.clear(); } catch (_) {}
    try { sessionStorage.clear(); } catch (_) {}
  } finally {
    location.replace('/?fresh=' + Date.now());
  }
})();
</script>
Resetting Nova3D...
</body>
</html>
"""
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Clear-Site-Data", '"cache", "storage", "executionContexts"')
            self.end_headers()
            self.wfile.write(body)
            return None

        translated = Path(self.translate_path(self.path))
        if translated.exists():
            return super().send_head()

        self.path = "/index.html"
        return super().send_head()

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5555)
    parser.add_argument("--directory", default="build/web")
    args = parser.parse_args()

    directory = Path(args.directory).resolve()
    if not directory.exists():
        raise SystemExit(f"Build directory not found: {directory}")

    handler = partial(SpaRequestHandler, directory=str(directory))
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"Serving {directory} on http://{args.host}:{args.port}/", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
