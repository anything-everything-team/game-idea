#!/usr/bin/env python3
"""Serve the web export locally.

    python3 tools/serve_web.py [directory] [port]

Defaults to build/web on port 8060. Sends the cross-origin isolation headers that a
threaded web build would need, so the same server works if threads are enabled later.
"""
import functools
import http.server
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "application/javascript",
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else "build/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8060
    handler = functools.partial(Handler, directory=directory)
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as server:
        print(f"Serving {directory} at http://127.0.0.1:{port}/")
        server.serve_forever()


if __name__ == "__main__":
    main()
