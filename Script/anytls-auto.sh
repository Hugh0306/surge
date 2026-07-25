#!/bin/sh
set -eu

PORT="${1:-61368}"
NAME="${2:-test}"
SNI="${3:-www.amd.com}"
DIR="/etc/sing-box"
BIN="/usr/local/bin/sing-box"
CONF="$DIR/config.json"
STATE="$DIR/anytls.env"
CERT="$DIR/cert.pem"
KEY="$DIR/key.pem"
TMP="/tmp/anytls-lite.$$"

[ "$(id -u)" = "0" ] || { echo "需要 root 权限" >&2; exit 1; }
case "$PORT" in *[!0-9]*|'') echo "端口无效" >&2; exit 1 ;; esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || { echo "端口无效" >&2; exit 1; }
mkdir -p "$TMP" "$DIR"
trap 'rm -rf "$TMP"' EXIT INT TERM

get() {
  if command -v curl >/dev/null 2>&1; then curl -LfsS --connect-timeout 10 "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then wget -q -T 15 "$1" -O "$2"
  else echo "缺少 curl/wget" >&2; exit 1
  fi
}

need_openssl() {
  command -v openssl >/dev/null 2>&1 && return 0
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache openssl >/dev/null 2>&1
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends openssl >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y -q install openssl >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum -y -q install openssl >/dev/null 2>&1
  else
    echo "缺少 openssl，且无法自动安装" >&2; exit 1
  fi
}

install_singbox() {
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    armv7l|armv7) ARCH=armv7 ;;
    *) echo "不支持的架构: $ARCH" >&2; exit 1 ;;
  esac

  VER="1.13.8"
  if get "https://api.github.com/repos/SagerNet/sing-box/releases/latest" "$TMP/release.json" 2>/dev/null; then
    LATEST="$(grep -m1 '"tag_name"' "$TMP/release.json" | sed -E 's/.*"v?([^\"]+)".*/\1/' || true)"
    [ -n "$LATEST" ] && VER="$LATEST"
  fi
  get "https://github.com/SagerNet/sing-box/releases/download/v${VER}/sing-box-${VER}-linux-${ARCH}.tar.gz" "$TMP/sing-box.tar.gz"
  tar -xzf "$TMP/sing-box.tar.gz" -C "$TMP"
  SB="$(find "$TMP" -type f -name sing-box | head -n1)"
  [ -n "$SB" ] || { echo "sing-box 解压失败" >&2; exit 1; }
  cp "$SB" "$BIN"
  chmod 755 "$BIN"
}

install_singbox
need_openssl

PASSWORD=""
if [ -f "$STATE" ]; then
  PASSWORD="$(sed -n "s/^PASSWORD='\(.*\)'$/\1/p" "$STATE" | head -n1)"
fi
PASSWORD="${PASSWORD:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)}"
[ -n "$PASSWORD" ] || PASSWORD="$(openssl rand -hex 16)"

if [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
  if ! openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
      -subj "/CN=$SNI" -addext "subjectAltName=DNS:$SNI" \
      -keyout "$KEY" -out "$CERT" >/dev/null 2>&1; then
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
      -subj "/CN=$SNI" -keyout "$KEY" -out "$CERT" >/dev/null 2>&1
  fi
  chmod 600 "$KEY"
fi

cat > "$CONF" <<EOF_CONFIG
{
  "log": {"level": "warn"},
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": $PORT,
      "users": [{"name": "default", "password": "$PASSWORD"}],
      "padding_scheme": ["stop=2", "0=100-200", "1=100-200"],
      "tls": {
        "enabled": true,
        "alpn": ["http/1.1"],
        "certificate_path": "$CERT",
        "key_path": "$KEY"
      }
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF_CONFIG

"$BIN" check -c "$CONF" >/dev/null 2>&1 || { echo "sing-box 配置校验失败" >&2; exit 1; }
cat > "$STATE" <<EOF_STATE
PASSWORD='$PASSWORD'
EOF_STATE
chmod 600 "$STATE"

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  cat > /etc/systemd/system/sing-box.service <<EOF_SYSTEMD
[Unit]
Description=sing-box AnyTLS
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN run -c $CONF
Restart=on-failure
RestartSec=2
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD
  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable sing-box >/dev/null 2>&1
  systemctl restart sing-box >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1; then
  cat > /etc/init.d/sing-box <<EOF_OPENRC
#!/sbin/openrc-run
command="$BIN"
command_args="run -c $CONF"
command_background="yes"
pidfile="/run/sing-box.pid"
output_log="/dev/null"
error_log="/dev/null"
depend() { need net; }
EOF_OPENRC
  chmod +x /etc/init.d/sing-box
  rc-update add sing-box default >/dev/null 2>&1 || true
  rc-service sing-box restart >/dev/null 2>&1 || rc-service sing-box start >/dev/null 2>&1
else
  PIDFILE="/run/sing-box.pid"
  if [ -s "$PIDFILE" ]; then kill "$(cat "$PIDFILE")" >/dev/null 2>&1 || true; fi
  nohup "$BIN" run -c "$CONF" >/dev/null 2>&1 &
  echo $! > "$PIDFILE"
fi

sleep 1
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl is-active --quiet sing-box || { echo "sing-box 启动失败" >&2; exit 1; }
elif command -v rc-service >/dev/null 2>&1; then
  rc-service sing-box status >/dev/null 2>&1 || { echo "sing-box 启动失败" >&2; exit 1; }
else
  kill -0 "$(cat /run/sing-box.pid)" >/dev/null 2>&1 || { echo "sing-box 启动失败" >&2; exit 1; }
fi

IP=""
if command -v curl >/dev/null 2>&1; then
  IP="$(curl -4fsS --connect-timeout 5 https://api.ipify.org 2>/dev/null || true)"
elif command -v wget >/dev/null 2>&1; then
  IP="$(wget -q -T 8 -O- https://api.ipify.org 2>/dev/null || true)"
fi
[ -n "$IP" ] || IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "$IP" ] || { echo "无法获取服务器 IP" >&2; exit 1; }

printf '%s = anytls, %s, %s, password=%s, sni=%s, skip-cert-verify=true, tfo=true, udp-relay=true\n' \
  "$NAME" "$IP" "$PORT" "$PASSWORD" "$SNI"
