#!/usr/bin/env python3
"""Serve an exported Godot Web game. Python 3 standard library only."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import webbrowser


class GameHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript; charset=utf-8",
        ".html": "text/html; charset=utf-8",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", default=str(Path(__file__).resolve().parents[1] / "build" / "web"))
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--open", action="store_true")
    args = parser.parse_args()
    directory = Path(args.directory).resolve()
    if not (directory / "index.html").is_file():
        parser.error(f"No index.html in {directory}. Export the game first.")
    server = ThreadingHTTPServer(("0.0.0.0", args.port), partial(GameHandler, directory=str(directory)))
    address = f"http://localhost:{args.port}/"
    print(f"Ты мой дом: {address}\nServing {directory}\nCtrl+C to stop.", flush=True)
    if args.open:
        webbrowser.open(address)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()

