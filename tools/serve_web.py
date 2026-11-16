"""Serve build/web-city on http://127.0.0.1:8060 for testing the browser build locally.

Uses only the Python standard library (Blender's bundled Python works):
    "<Blender>\\5.3\\python\\bin\\python.exe" -I tools\\serve_web.py [port]

Like GitHub Pages it gzips responses (.glb, .wasm, .pck, .js, .html), sends .wasm as
application/wasm and lets the browser cache the
city tiles. Logs one line per tile so you can watch the streaming.
"""
import functools
import gzip
import http.server
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web-city")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
SHOTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "screens", "web")


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".pck": "application/octet-stream",
                      ".glb": "model/gltf-binary", ".js": "text/javascript"}

    def end_headers(self):
        if self.path.startswith("/city/"):
            self.send_header("Cache-Control", "public, max-age=86400")
        else:
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def do_GET(self):
        # Compress like GitHub Pages does (Content-Encoding: gzip), so a local test behaves
        # like the live site - the browser unpacks it before the game sees it.
        path = self.translate_path(self.path.split("?")[0])
        gz_types = (".glb", ".wasm", ".pck", ".js", ".html")
        if (os.path.isfile(path) and path.endswith(gz_types)
                and "gzip" in self.headers.get("Accept-Encoding", "")):
            with open(path, "rb") as f:
                body = gzip.compress(f.read(), compresslevel=6)
            self.send_response(200)
            self.send_header("Content-Type", self.guess_type(path))
            self.send_header("Content-Encoding", "gzip")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def do_POST(self):
        # the browser benchmark posts screenshots here: /shot/<name> -> build/screens/web/<name>.png
        name = os.path.basename(self.path.split("?")[0])
        if not self.path.startswith("/shot/") or not name.replace("_", "").isalnum():
            self.send_error(404)
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        out = os.path.join(SHOTS, name + ".png")
        os.makedirs(SHOTS, exist_ok=True)
        with open(out, "wb") as f:
            f.write(body)
        self.send_response(204)
        self.end_headers()

    def log_message(self, fmt, *args):
        sys.stdout.write("%s\n" % (fmt % args))
        sys.stdout.flush()


if __name__ == "__main__":
    os.chdir(ROOT)
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), functools.partial(Handler, directory=ROOT))
    print("serving %s on http://127.0.0.1:%d/" % (os.path.abspath(ROOT), PORT), flush=True)
    httpd.serve_forever()
