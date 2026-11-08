#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
web_dir="$root/game/build/web"
port="${PORT:-8080}"
tls_port="${TLS_PORT:-8443}"
cert_dir="$root/.certs"

if [[ ! -f "$web_dir/index.html" ]]; then
	echo "error: $web_dir/index.html missing. Run scripts/export.sh first." >&2
	exit 1
fi

# The default-route source address is the interface a phone on the LAN can reach.
lan_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1)"
lan_ip="${lan_ip:-127.0.0.1}"

# Fullscreen and orientation lock need a secure context, so the phone must open the https URL.
# The cert is bound to the LAN IP, so a new IP needs a new cert.
if [[ ! -f "$cert_dir/cert.pem" ]] || ! openssl x509 -in "$cert_dir/cert.pem" -noout -ext subjectAltName 2>/dev/null | grep -q "IP Address:$lan_ip"; then
	mkdir -p "$cert_dir"
	openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=hot-shift-dev" \
		-addext "subjectAltName=IP:$lan_ip,IP:127.0.0.1,DNS:localhost" \
		-keyout "$cert_dir/key.pem" -out "$cert_dir/cert.pem" 2>/dev/null
fi

url="https://$lan_ip:$tls_port"

echo "Serving $web_dir"
echo "Local: http://127.0.0.1:$port"
echo "LAN:   $url   (self-signed, accept the warning once)"
echo "LAN:   http://$lan_ip:$port   (no fullscreen lock)"
if command -v qrencode >/dev/null 2>&1; then
	qrencode -t ANSIUTF8 "$url"
else
	echo "(install qrencode to print a QR code)"
fi

python3 "$root/scripts/serve.py" "$web_dir" "$port" &
http_pid=$!
trap 'kill "$http_pid" 2>/dev/null || true' EXIT INT TERM
python3 "$root/scripts/serve.py" "$web_dir" "$tls_port" "$cert_dir/cert.pem" "$cert_dir/key.pem"
