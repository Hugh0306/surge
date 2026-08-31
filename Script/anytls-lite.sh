#!/bin/sh
set -eu
P="${1:-}"
case "$P" in ''|*[!0-9]*) printf '端口: '; read -r P;; esac
[ "$P" -ge 1 ] 2>/dev/null && [ "$P" -le 65535 ] || { echo '端口无效'; exit 1; }
S=www.icloud.com; D=/etc/sing-box; B=/usr/local/bin/sing-box
command -v curl >/dev/null || (command -v apk >/dev/null && apk add --no-cache curl openssl) || (apt-get update -qq && apt-get install -y -qq curl openssl)
command -v openssl >/dev/null || (command -v apk >/dev/null && apk add --no-cache openssl) || apt-get install -y -qq openssl
if [ ! -x "$B" ]; then
 V=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest|sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p'|head -1); A=$(uname -m); [ "$A" = x86_64 ]&&A=amd64; [ "$A" = aarch64 ]&&A=arm64
 T=$(mktemp -d); curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v$V/sing-box-$V-linux-$A.tar.gz"|tar xz -C "$T"; install -m755 "$T/sing-box-$V-linux-$A/sing-box" "$B"; rm -rf "$T"
fi
W=$(cat /proc/sys/kernel/random/uuid 2>/dev/null||openssl rand -hex 16); mkdir -p "$D"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 -subj "/CN=$S" -keyout "$D/key.pem" -out "$D/cert.pem" >/dev/null 2>&1
cat >"$D/config.json" <<EOF
{"inbounds":[{"type":"anytls","listen":"::","listen_port":$P,"users":[{"password":"$W"}],"tls":{"enabled":true,"certificate_path":"$D/cert.pem","key_path":"$D/key.pem"}}],"outbounds":[{"type":"direct"}]}
EOF
if command -v systemctl >/dev/null; then printf '[Unit]\nAfter=network.target\n[Service]\nExecStart=%s run -c %s/config.json\nRestart=always\n[Install]\nWantedBy=multi-user.target\n' "$B" "$D" >/etc/systemd/system/sing-box.service; systemctl daemon-reload; systemctl enable --now sing-box >/dev/null 2>&1; systemctl restart sing-box; else printf '#!/sbin/openrc-run\ncommand="%s"\ncommand_args="run -c %s/config.json"\ncommand_background=yes\npidfile=/run/sing-box.pid\n' "$B" "$D" >/etc/init.d/sing-box; chmod +x /etc/init.d/sing-box; rc-update add sing-box default >/dev/null 2>&1||:; rc-service sing-box restart >/dev/null 2>&1||rc-service sing-box start >/dev/null; fi
IP=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null||echo SERVER_IP)
echo "AnyTLS = anytls, $IP, $P, password=$W, sni=$S, skip-cert-verify=true, tfo=true, udp-relay=true"