#!/usr/bin/env bash
set -u
set -o pipefail

# Hugh0306 AnyTLS one-shot installer
# Logic: install/update sing-box core [14] -> add node [1] -> AnyTLS [5]
# Defaults: AnyTLS mode, default server IP, port 61368, default SNI www.amd.com,
#           random password, node name test, auto self-signed cert.

PATCHED_SB_URL="https://raw.githubusercontent.com/Hugh0306/surge/main/Script/singbox-surge.sh"
TARGET="/usr/local/bin/sb"
PORT="${1:-61368}"
NODE_NAME="${2:-test}"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "[错误] 请使用 root 权限运行：sudo bash $0" >&2
  exit 1
fi

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
  echo "[错误] 端口无效：$PORT。端口范围应为 1024-65535。" >&2
  exit 1
fi

if [ -z "$NODE_NAME" ]; then
  NODE_NAME="test"
fi

download() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -LfsS "$url" -o "$out" && return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$out" && return 0
  fi
  echo "[错误] curl/wget 均不可用，无法下载脚本。" >&2
  return 1
}

strip_ansi() {
  sed -E $'s/\x1B\[[0-9;?]*[ -/]*[@-~]//g'
}

TMP_LOADER="$(mktemp /tmp/anytls-sb-loader.XXXXXX)"
TMP_OUTPUT="$(mktemp /tmp/anytls-output.XXXXXX)"
trap 'rm -f "$TMP_LOADER" "$TMP_OUTPUT"' EXIT

echo "[信息] 下载 Surge 输出增强版 singbox 脚本..."
download "$PATCHED_SB_URL" "$TMP_LOADER" || exit 1
chmod +x "$TMP_LOADER"

echo "[信息] 自动执行：14 -> 1 -> 5 -> AnyTLS:${PORT}，节点名 ${NODE_NAME}，其余选项使用默认值。"

# Input mapping:
# 14        main menu: install/update sing-box core
# x1        x consumed by "press any key", then 1 enters add-node menu
# 5         add-node menu: AnyTLS
# blank     AnyTLS mode: default 1 = AnyTLS
# blank     server IP: default current public IP
# PORT      listen port
# blank     SNI: default www.amd.com
# blank     password/UUID: random
# NODE_NAME node name: default test
# blank     cert type: default auto self-signed
# x0        x consumed by "press any key", then 0 exits main menu
{
  printf '14\n'
  printf 'x1\n'
  printf '5\n'
  printf '\n'
  printf '\n'
  printf '%s\n' "$PORT"
  printf '\n'
  printf '\n'
  printf '%s\n' "$NODE_NAME"
  printf '\n'
  printf 'x0\n'
} | bash "$TMP_LOADER" 2>&1 | tee "$TMP_OUTPUT"

CLEAN_OUTPUT="$(strip_ansi < "$TMP_OUTPUT")"
SURGE_LINE="$(printf '%s\n' "$CLEAN_OUTPUT" | grep -E '^[^=]+ = anytls, ' | tail -n 1 || true)"
RAW_LINK="$(printf '%s\n' "$CLEAN_OUTPUT" | grep -E '^anytls://' | tail -n 1 || true)"

printf '\n'
echo "════════════════ AnyTLS 输出结果 ════════════════"
if [ -n "$SURGE_LINE" ]; then
  echo "$SURGE_LINE"
  echo "══════════════════════════════════════════════════"
  exit 0
fi

if [ -n "$RAW_LINK" ]; then
  echo "[注意] 未提取到 Surge 单行格式，仅检测到原始 AnyTLS 链接："
  echo "$RAW_LINK"
  echo "══════════════════════════════════════════════════"
  exit 0
fi

echo "[错误] 未检测到 AnyTLS 节点输出。请检查上方日志，常见原因：端口被占用、核心安装失败、网络无法访问 GitHub。" >&2
echo "══════════════════════════════════════════════════"
exit 1
