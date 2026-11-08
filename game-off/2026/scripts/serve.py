#!/usr/bin/env python3
"""Serve a directory over HTTP or HTTPS with the wasm MIME type, gzip and revalidation."""
import functools
import gzip
import hashlib
import http.server
import os
import shutil
import ssl
import sys
import tempfile
import time
import urllib.parse

COMPRESSIBLE = {".wasm", ".js", ".pck", ".html", ".json"}
GZIP_DIR = os.path.join(tempfile.gettempdir(), "hot-shift-gzip")


def gzip_copy(path: str) -> str:
    """Return a gzip copy of path, rebuilt only when the source changes."""
    stat = os.stat(path)
    key = hashlib.sha1(f"{path}:{stat.st_mtime_ns}:{stat.st_size}".encode()).hexdigest()
    target = os.path.join(GZIP_DIR, key + ".gz")
    if not os.path.exists(target):
        os.makedirs(GZIP_DIR, exist_ok=True)
        partial = target + f".{os.getpid()}.tmp"
        with open(path, "rb") as source, gzip.open(partial, "wb", compresslevel=6) as sink:
            shutil.copyfileobj(source, sink)
        os.replace(partial, target)
    return target


class Handler(http.server.SimpleHTTPRequestHandler):
    timeout = 30

    def setup(self) -> None:
        if isinstance(self.request, ssl.SSLSocket):
            self.request.settimeout(15)
            self.request.do_handshake()
        super().setup()

    def do_GET(self) -> None:
        if self.path.startswith("/__log"):
            # Dev only: a phone has no console, so the page reports its progress here with ?debug=1.
            message = urllib.parse.unquote(urllib.parse.urlparse(self.path).query)
            print(f"CLIENT {self.client_address[0]} {message}", flush=True)
            self.send_response(204)
            self.end_headers()
            return
        super().do_GET()

    def copyfile(self, source, outputfile) -> None:
        sent = 0
        started = time.monotonic()
        try:
            while chunk := source.read(65536):
                outputfile.write(chunk)
                sent += len(chunk)
        except (ConnectionError, ssl.SSLError, TimeoutError) as err:
            self.log_message("ABORTED %s after %d bytes in %.1fs: %s", self.path, sent, time.monotonic() - started, type(err).__name__)
            raise
        if sent > 1_000_000:
            self.log_message("SENT %s %d bytes in %.1fs", self.path, sent, time.monotonic() - started)

    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".pck": "application/octet-stream",
    }

    def end_headers(self) -> None:
        # no-cache lets the browser keep the file but ask again, so a reload sends 304 not 37 MB.
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def send_head(self):
        path = self.translate_path(self.path)
        extension = os.path.splitext(path)[1]
        wants_gzip = "gzip" in self.headers.get("Accept-Encoding", "")
        if extension not in COMPRESSIBLE or not wants_gzip or not os.path.isfile(path):
            return super().send_head()
        source_mtime = os.stat(path).st_mtime
        since = self.headers.get("If-Modified-Since")
        if since:
            try:
                if int(source_mtime) <= int(http.server.email.utils.parsedate_to_datetime(since).timestamp()):
                    self.send_response(304)
                    self.end_headers()
                    return None
            except (TypeError, ValueError):
                pass
        packed = open(gzip_copy(path), "rb")
        self.send_response(200)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length", str(os.fstat(packed.fileno()).st_size))
        self.send_header("Last-Modified", self.date_time_string(source_mtime))
        self.send_header("Vary", "Accept-Encoding")
        self.end_headers()
        return packed


class Server(http.server.ThreadingHTTPServer):
    request_queue_size = 64

    def handle_error(self, request, client_address) -> None:
        # Browsers drop speculative connections, so these are routine and not worth a traceback.
        if isinstance(sys.exc_info()[1], (ssl.SSLError, ConnectionError, TimeoutError)):
            return
        super().handle_error(request, client_address)


def main() -> None:
    directory, port = sys.argv[1], int(sys.argv[2])
    handler = functools.partial(Handler, directory=directory)
    with Server(("0.0.0.0", port), handler) as server:
        if len(sys.argv) == 5:
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(certfile=sys.argv[3], keyfile=sys.argv[4])
            # The handshake must run in the request thread. In the accept loop one idle client blocks every other client.
            server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
        server.serve_forever()


if __name__ == "__main__":
    main()
