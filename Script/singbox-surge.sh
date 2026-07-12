#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_URL="https://raw.githubusercontent.com/0xdabiaoge/singbox-lite/main/singbox.sh"
SELF_UPDATE_URL="https://raw.githubusercontent.com/Hugh0306/surge/main/Script/singbox-surge.sh"
TARGET="/usr/local/bin/sb"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "[错误] 请使用 root 权限运行：sudo bash $0" >&2
  exit 1
fi

tmpdir="$(mktemp -d /tmp/sb-surge.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT
orig="$tmpdir/singbox.sh"
patched1="$tmpdir/singbox.1.sh"
patched2="$tmpdir/singbox.2.sh"
patched3="$tmpdir/singbox.3.sh"
helper="$tmpdir/helper.txt"
insert="$tmpdir/insert.txt"

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

download "$UPSTREAM_URL" "$orig"

cat > "$helper" <<'HELPER_EOF'

# Hugh0306 patch: non-VLESS share output as Surge proxy line
_surge_escape_value() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/,/\\,/g'
}
_surge_skip_bool() {
    case "${1:-}" in
        true|1|yes|YES|y|Y) printf 'true' ;;
        *) printf 'false' ;;
    esac
}
_singboxlite_surge_line() {
    local type="$1" name="$2" server="$3" port="$4"
    shift 4

    case "$type" in
        vless*) return 1 ;;
    esac

    local n="$(_surge_escape_value "$name")"
    local s="$(_surge_escape_value "$server")"

    case "$type" in
        "trojan-ws-tls")
            local password="$1" sni="${2:-$DEFAULT_SNI}" ws_path="$3" skip_verify="$4"
            printf '%s = trojan, %s, %s, password=%s, sni=%s, ws=true, ws-path=%s, ws-headers=Host:%s, skip-cert-verify=%s, udp-relay=true' \
                "$n" "$s" "$port" "$(_surge_escape_value "$password")" "$(_surge_escape_value "$sni")" "$(_surge_escape_value "$ws_path")" "$(_surge_escape_value "$sni")" "$(_surge_skip_bool "$skip_verify")"
            ;;
        "trojan-ws")
            local password="$1" ws_path="$2"
            local ed_path="$(_ws_path_with_early_data "$ws_path")"
            printf '%s = trojan, %s, 443, password=%s, sni=%s, ws=true, ws-path=%s, ws-headers=Host:%s, skip-cert-verify=false, udp-relay=true' \
                "$n" "$s" "$(_surge_escape_value "$password")" "$s" "$(_surge_escape_value "$ed_path")" "$s"
            ;;
        "hysteria2")
            local password="$1" sni="${2:-$DEFAULT_SNI}" obfs_password="$3" port_hopping="$4"
            local line
            line=$(printf '%s = hysteria2, %s, %s, password=%s, sni=%s, skip-cert-verify=true, udp-relay=true' \
                "$n" "$s" "$port" "$(_surge_escape_value "$password")" "$(_surge_escape_value "$sni")")
            [ -n "$obfs_password" ] && line="${line}, obfs=salamander, obfs-password=$(_surge_escape_value "$obfs_password")"
            [ -n "$port_hopping" ] && line="${line}, port-hopping=${port_hopping}"
            printf '%s' "$line"
            ;;
        "tuic")
            local uuid="$1" password="$2" sni="${3:-$DEFAULT_SNI}"
            printf '%s = tuic, %s, %s, uuid=%s, password=%s, sni=%s, alpn=h3, congestion-controller=bbr, udp-relay=true, skip-cert-verify=true' \
                "$n" "$s" "$port" "$(_surge_escape_value "$uuid")" "$(_surge_escape_value "$password")" "$(_surge_escape_value "$sni")"
            ;;
        "anytls")
            local password="$1" sni="${2:-$DEFAULT_SNI}" skip_verify="$3"
            printf '%s = anytls, %s, %s, password=%s, sni=%s, skip-cert-verify=%s, tfo=true, udp-relay=true' \
                "$n" "$s" "$port" "$(_surge_escape_value "$password")" "$(_surge_escape_value "$sni")" "$(_surge_skip_bool "$skip_verify")"
            ;;
        "any-reality")
            local password="$1" sni="${2:-$DEFAULT_SNI}" public_key="$3" short_id="$4"
            printf '%s = anytls, %s, %s, password=%s, sni=%s, security=reality, fingerprint=chrome, public-key=%s, short-id=%s, tfo=true, udp-relay=true' \
                "$n" "$s" "$port" "$(_surge_escape_value "$password")" "$(_surge_escape_value "$sni")" "$(_surge_escape_value "$public_key")" "$(_surge_escape_value "$short_id")"
            ;;
        "shadowsocks")
            local method="$1" password="$2"
            printf '%s = ss, %s, %s, encrypt-method=%s, password=%s, udp-relay=true' \
                "$n" "$s" "$port" "$(_surge_escape_value "$method")" "$(_surge_escape_value "$password")"
            ;;
        "shadowsocks-shadowtls")
            local method="$1" pw="$2" spw="$3" sni="$4"
            printf '%s = ss, %s, %s, encrypt-method=%s, password=%s, udp-relay=true, shadow-tls-password=%s, shadow-tls-sni=%s, shadow-tls-version=3' \
                "$n" "$s" "$port" "$(_surge_escape_value "$method")" "$(_surge_escape_value "$pw")" "$(_surge_escape_value "$spw")" "$(_surge_escape_value "$sni")"
            ;;
        "socks")
            local username="$1" password="$2"
            if [ -n "$username" ]; then
                printf '%s = socks5, %s, %s, username=%s, password=%s, udp-relay=true' \
                    "$n" "$s" "$port" "$(_surge_escape_value "$username")" "$(_surge_escape_value "$password")"
            else
                printf '%s = socks5, %s, %s, udp-relay=true' "$n" "$s" "$port"
            fi
            ;;
        *) return 1 ;;
    esac
}
HELPER_EOF

cat > "$insert" <<'INSERT_EOF'

    # Hugh0306 patch: keep VLESS share links; convert all other generated node outputs to Surge proxy-line format.
    if [ -n "$url" ] && [[ "$type" != vless* ]]; then
        local surge_line
        surge_line="$(_singboxlite_surge_line "$type" "$name" "$link_ip" "$port" "$@" 2>/dev/null || true)"
        [ -n "$surge_line" ] && url="$surge_line"
    fi
INSERT_EOF

# 1) Insert helper before _show_node_link
awk -v helper="$helper" '
BEGIN {
  while ((getline l < helper) > 0) h = h l "\n";
  close(helper);
}
/^# 显示节点分享链接/ { printf "%s", h }
{ print }
' "$orig" > "$patched1"

# 2) Insert conversion after the first esac inside _show_node_link
awk -v insert="$insert" '
BEGIN {
  while ((getline l < insert) > 0) ins = ins l "\n";
  close(insert);
}
/^_show_node_link\(\) \{/ { in_show=1 }
in_show && /^    esac$/ && !done_insert { print; printf "%s", ins; done_insert=1; next }
{ print }
' "$patched1" > "$patched2"

# 3) Make ShadowTLS also emit a Surge line instead of only Clash/Mihomo snippet
sed '/"shadowsocks-shadowtls")/,/;;/ s|^[[:space:]]*url=""|            url="$(_singboxlite_surge_line "$type" "$name" "$link_ip" "$port" "$method" "$pw" "$spw" "$sni")"|' "$patched2" > "$patched3"

# 4) Make script self-update back to this patched loader, not the original upstream script
sed "s|^SCRIPT_UPDATE_URL=.*|SCRIPT_UPDATE_URL=\"${SELF_UPDATE_URL}\"|" "$patched3" > "$TARGET.new"

chmod +x "$TARGET.new"
mv -f "$TARGET.new" "$TARGET"
exec "$TARGET" "$@"
