#!/bin/sh
set -u
URL="https://raw.githubusercontent.com/Hugh0306/surge/main/Script/mihomo-surge.sh"
DST="/usr/local/bin/mh"

[ "$(id -u)" = "0" ] || { echo "[错误] 请使用 root 权限运行" >&2; exit 1; }

if ! command -v curl >/dev/null 2>&1; then
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache ca-certificates curl >/dev/null || exit 1
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl >/dev/null || exit 1
  else
    echo "[错误] 缺少 curl，且无法自动安装" >&2
    exit 1
  fi
fi

TMP="/tmp/mh-install.$$"
trap 'rm -f "$TMP"' EXIT INT TERM
curl -LfsS "$URL" -o "$TMP" || { echo "[错误] 下载 Mihomo Surge Lite 失败" >&2; exit 1; }
sh -n "$TMP" || { echo "[错误] 脚本语法校验失败" >&2; exit 1; }
install -m 755 "$TMP" "$DST" 2>/dev/null || { cp "$TMP" "$DST" && chmod 755 "$DST"; }

echo "[成功] Mihomo Surge Lite 已安装为命令: mh"
exec "$DST" "$@"
