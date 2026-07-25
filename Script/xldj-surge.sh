#!/usr/bin/env bash
set -euo pipefail

# Upstream is an interactive manager. Do not run this wrapper through `curl | bash`.
if [ ! -t 0 ]; then
    echo "[错误] 这是交互式脚本，不能使用 curl | bash 管道运行。" >&2
    echo "[提示] 请先下载文件，再执行：bash /tmp/xldj.sh" >&2
    exit 1
fi

UPSTREAM_URL="https://raw.githubusercontent.com/shini74744/Shliixg/refs/heads/main/xldj.sh"
TMP_DIR="$(mktemp -d /tmp/xldj-surge.XXXXXX)"
SRC="$TMP_DIR/xldj.sh"
PATCHED="$TMP_DIR/xldj-surge.sh"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

if command -v curl >/dev/null 2>&1; then
    curl -LfsS "$UPSTREAM_URL" -o "$SRC"
elif command -v wget >/dev/null 2>&1; then
    wget -q "$UPSTREAM_URL" -O "$SRC"
else
    echo "[错误] 缺少 curl/wget" >&2
    exit 1
fi

# Keep the upstream script unchanged except for the node-output function.
awk '/^_show_node_link\(\) \{/{exit} {print}' "$SRC" > "$PATCHED"
cat >> "$PATCHED" <<'EOF_SURGE_FUNCTION'
_show_node_link() {
    local type="$1"
    local name="$2"
    local link_ip="$3"
    local port="$4"
    local tag="$5"

    if [[ "$link_ip" == *":"* ]] && [[ "$link_ip" != "["* ]]; then
        link_ip="[${link_ip}]"
    fi

    shift 5
    local url=""

    case "$type" in
        "vless-reality")
            local uuid="$1" pk="$3" sid="$4" flow="${5:-xtls-rprx-vision}"
            local sni
            sni=$(echo "$2" | xargs)
            [[ -z "$sni" ]] && sni="$DEFAULT_SNI"
            url="vless://${uuid}@${link_ip}:${port}?security=reality&encryption=none&pbk=$(_url_encode "${pk}")&fp=chrome&type=tcp&flow=${flow}&sni=${sni}&sid=${sid}#$(_url_encode "$name")"
            ;;
        "vless-ws-tls")
            local uuid="$1" sni="${2:-$DEFAULT_SNI}" ws_path="$3" skip_verify="${4:-false}"
            local insecure_param=""
            [[ "$skip_verify" == "true" ]] && insecure_param="&insecure=1&allowInsecure=1"
            url="vless://${uuid}@${link_ip}:${port}?security=tls&encryption=none&type=ws&host=${sni}&path=$(_url_encode "$ws_path")&sni=${sni}${insecure_param}#$(_url_encode "$name")"
            ;;
        "vless-tcp")
            local uuid="$1"
            url="vless://${uuid}@${link_ip}:${port}?encryption=none&type=tcp#$(_url_encode "$name")"
            ;;
        "trojan-ws-tls")
            local password="$1" sni="${2:-$DEFAULT_SNI}" ws_path="$3" skip_verify="${4:-false}"
            url="${name} = trojan, ${link_ip}, ${port}, password=${password}, sni=${sni}, ws=true, ws-path=${ws_path}, ws-headers=Host:${sni}, skip-cert-verify=${skip_verify}, udp-relay=true"
            ;;
        "hysteria2")
            local password="$1" sni="${2:-$DEFAULT_SNI}" obfs_password="${3:-}" port_hopping="${4:-}"
            url="${name} = hysteria2, ${link_ip}, ${port}, password=${password}, sni=${sni}, alpn=h3, skip-cert-verify=true"
            [[ -n "$obfs_password" ]] && url="${url}, salamander-password=${obfs_password}"
            [[ -n "$port_hopping" ]] && url="${url}, port-hopping=${port_hopping}"
            ;;
        "tuic")
            local uuid="$1" password="$2" sni="${3:-$DEFAULT_SNI}"
            url="${name} = tuic-v5, ${link_ip}, ${port}, uuid=${uuid}, password=${password}, sni=${sni}, alpn=h3, skip-cert-verify=true"
            ;;
        "anytls")
            local password="$1" sni="${2:-$DEFAULT_SNI}" skip_verify="${3:-false}"
            url="${name} = anytls, ${link_ip}, ${port}, password=${password}, sni=${sni}, skip-cert-verify=${skip_verify}"
            ;;
        "shadowsocks")
            local method="$1" password="$2"
            url="${name} = ss, ${link_ip}, ${port}, encrypt-method=${method}, password=${password}, udp-relay=true"
            ;;
        "shadowsocks-shadowtls")
            local method="$1" pw="$2" spw="$3" sni="$4"
            url="${name} = ss, ${link_ip}, ${port}, encrypt-method=${method}, password=${pw}, shadow-tls-password=${spw}, shadow-tls-sni=${sni}, shadow-tls-version=3"
            ;;
        "vless-ws")
            local uuid="$1" ws_path="$2"
            url="vless://${uuid}@${link_ip}:443?encryption=none&security=tls&type=ws&host=${link_ip}&path=$(_url_encode "$ws_path")&sni=${link_ip}#$(_url_encode "$name")"
            ;;
        "trojan-ws")
            local password="$1" ws_path="$2"
            url="${name} = trojan, ${link_ip}, 443, password=${password}, sni=${link_ip}, ws=true, ws-path=${ws_path}, ws-headers=Host:${link_ip}, skip-cert-verify=false, udp-relay=true"
            ;;
        "socks")
            local username="$1" password="$2"
            url="${name} = socks5, ${link_ip}, ${port}, ${username}, ${password}, udp-relay=true"
            ;;
    esac

    if [ -n "$url" ]; then
        echo ""
        echo -e "${YELLOW}═══════════════════ 分享链接 ═══════════════════${NC}"
        echo -e "${CYAN}${url}${NC}"
        echo -e "${YELLOW}═════════════════════════════════════════════════${NC}"

        if [ -n "$tag" ] && [ "$tag" != "null" ]; then
            if [[ "$tag" == argo-* ]]; then
                _atomic_modify_json "$ARGO_METADATA_FILE" ". + { \"$tag\": ((.[\"$tag\"] // {}) + { \"share_link\": \"$url\" }) }"
            else
                _atomic_modify_json "$METADATA_FILE" ". + { \"$tag\": ((.[\"$tag\"] // {}) + { \"share_link\": \"$url\" }) }"
            fi
        fi
    fi
}

EOF_SURGE_FUNCTION

awk 'f || /^_show_cdn_guidance\(\) \{/{f=1; print}' "$SRC" >> "$PATCHED"

# Upstream main menu redraws forever when `read` receives EOF. Convert that case
# into a clean exit so a broken terminal can never produce a flashing loop.
sed -i 's@^[[:space:]]*read -p "  请输入选项 \[0-18\]: " choice@        if ! read -r -p "  请输入选项 [0-18]: " choice; then echo; exit 0; fi@' "$PATCHED" || true

chmod +x "$PATCHED"
bash "$PATCHED" "$@"
