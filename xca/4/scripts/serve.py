"""Serve build/ over HTTPS on 0.0.0.0:8446 with the self-signed certificate of the other spikes."""
import http.server
import pathlib
import ssl
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD_DIR = ROOT / "build"
CERT_DIR = ROOT / "cert"
PORT = 8446


def lan_addresses() -> list[str]:
    output = subprocess.run(["hostname", "-I"], capture_output=True, text=True, check=True).stdout
    return [a for a in output.split() if "." in a]


def ensure_certificate() -> tuple[pathlib.Path, pathlib.Path]:
    CERT_DIR.mkdir(exist_ok=True)
    cert, key = CERT_DIR / "cert.pem", CERT_DIR / "key.pem"
    if cert.exists() and key.exists():
        return cert, key
    names = ["DNS:localhost", "IP:127.0.0.1"] + [f"IP:{a}" for a in lan_addresses()]
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30",
        "-keyout", str(key), "-out", str(cert), "-subj", "/CN=rails-spike",
        "-addext", "subjectAltName=" + ",".join(names),
    ], check=True, capture_output=True)
    return cert, key


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
        ".mjs": "text/javascript",
        ".task": "application/octet-stream",
        ".tflite": "application/octet-stream",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(BUILD_DIR), **kwargs)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    cert, key = ensure_certificate()
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    for address in lan_addresses():
        print(f"https://{address}:{PORT}/", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
