#!/bin/sh
set -u

VERSION="1.0.0-hugh"
BIN="/usr/local/bin/mihomo"
SELF="/usr/local/bin/mh"
DIR="/etc/mihomo"
CONF="$DIR/config.yaml"
DB="$DIR/nodes.db"
RUNTIME="$DIR/runtime.env"
CERT_DIR="$DIR/certs"
LOG_DIR="/var/log/mihomo"
SERVICE="mihomo"
DEFAULT_SNI="www.amd.com"
API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"

say() { printf '%s\n' "$*"; }
err() { printf '[错误] %s\n' "$*" >&2; }
ok() { printf '[成功] %s\n' "$*"; }
info() { printf '[信息] %s\n' "$*"; }

need_root() {
  [ "$(id -u)" = "0" ] || { err "请使用 root 权限运行"; exit 1; }
}

install_pkgs() {
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache ca-certificates curl gzip openssl openrc >/dev/null
    mkdir -p /run/openrc 2>/dev/null || true
    touch /run/openrc/softlevel 2>/dev/null || true
    update-ca-certificates >/dev/null 2>&1 || true
  elif command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends ca-certificates curl gzip openssl >/dev/null
  else
    err "仅支持 Alpine / Debian / Ubuntu"
    exit 1
  fi
}

arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    armv7l|armv7) printf 'armv7' ;;
    *) err "不支持的架构: $(uname -m)"; exit 1 ;;
  esac
}

mem_limit_mib() {
  b=""
  if [ -r /sys/fs/cgroup/memory.max ]; then
    b="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || true)"
    [ "$b" = "max" ] && b=""
  fi
  if [ -z "$b" ] && [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    b="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || true)"
  fi
  case "$b" in ''|*[!0-9]*) return 1 ;; esac
  [ "$b" -lt 1099511627776 ] || return 1
  echo $((b / 1024 / 1024))
}

write_runtime_defaults() {
  [ -f "$RUNTIME" ] && return 0
  m="$(mem_limit_mib 2>/dev/null || echo 0)"
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  if [ "$m" -gt 0 ] && [ "$m" -le 80 ]; then
    ml="40MiB"; gc="300"; cpus="1"
  elif [ "$m" -gt 0 ] && [ "$m" -le 160 ]; then
    ml="80MiB"; gc="250"; cpus="1"
  elif [ "$m" -gt 0 ] && [ "$m" -le 320 ]; then
    ml="160MiB"; gc="220"; cpus="1"
  else
    ml="384MiB"; gc="200"; cpus="2"
  fi
  cat > "$RUNTIME" <<EOF_RUNTIME
GOMEMLIMIT=$ml
GOGC=$gc
GOMAXPROCS=$cpus
GODEBUG=madvdontneed=1
EOF_RUNTIME
  chmod 600 "$RUNTIME"
}

load_runtime() {
  write_runtime_defaults
  . "$RUNTIME"
  export GOMEMLIMIT GOGC GOMAXPROCS GODEBUG
}

latest_url() {
  a="$(arch)"
  json="$(curl -fsSL "$API")" || { err "无法访问 Mihomo Release API"; exit 1; }
  urls="$(printf '%s\n' "$json" | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  url="$(printf '%s\n' "$urls" | grep -Ei "mihomo-linux-${a}.*compatible.*\\.gz$" | head -n1 || true)"
  [ -n "$url" ] || url="$(printf '%s\n' "$urls" | grep -Ei "mihomo-linux-${a}.*\\.gz$" | head -n1 || true)"
  [ -n "$url" ] || { err "找不到适配 linux-$a 的 Mihomo"; exit 1; }
  printf '%s' "$url"
}

service_manager() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    echo systemd
  elif command -v rc-service >/dev/null 2>&1; then
    echo openrc
  else
    echo none
  fi
}

write_service() {
  load_runtime
  mgr="$(service_manager)"
  case "$mgr" in
    systemd)
      cat > /etc/systemd/system/mihomo.service <<EOF_SYSTEMD
[Unit]
Description=Mihomo Surge Lite
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=GOMEMLIMIT=$GOMEMLIMIT
Environment=GOGC=$GOGC
Environment=GOMAXPROCS=$GOMAXPROCS
Environment=GODEBUG=$GODEBUG
ExecStart=$BIN -d $DIR -f $CONF
Restart=on-failure
RestartSec=2
LimitNOFILE=65535
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD
      systemctl daemon-reload >/dev/null 2>&1
      systemctl enable "$SERVICE" >/dev/null 2>&1
      ;;
    openrc)
      cat > /etc/init.d/mihomo <<EOF_OPENRC
#!/sbin/openrc-run
description="Mihomo Surge Lite"
command="$BIN"
command_args="-d $DIR -f $CONF"
supervisor="supervise-daemon"
respawn_delay=2
respawn_max=0
output_log="/dev/null"
error_log="/dev/null"
rc_ulimit="-n 65535"
export GOMEMLIMIT="$GOMEMLIMIT"
export GOGC="$GOGC"
export GOMAXPROCS="$GOMAXPROCS"
export GODEBUG="$GODEBUG"
depend() { need net; }
EOF_OPENRC
      chmod +x /etc/init.d/mihomo
      rc-update add mihomo default >/dev/null 2>&1 || true
      ;;
    *) err "未检测到 systemd/OpenRC"; exit 1 ;;
  esac
}

restart_service() {
  case "$(service_manager)" in
    systemd) systemctl restart "$SERVICE" ;;
    openrc) rc-service "$SERVICE" restart >/dev/null 2>&1 || rc-service "$SERVICE" start >/dev/null 2>&1 ;;
    *) err "无法管理 Mihomo 服务"; return 1 ;;
  esac
}

status_text() {
  if [ ! -x "$BIN" ]; then echo "未安装"; return; fi
  case "$(service_manager)" in
    systemd) systemctl is-active --quiet "$SERVICE" 2>/dev/null && echo "运行中" || echo "已停止" ;;
    openrc) rc-service "$SERVICE" status >/dev/null 2>&1 && echo "运行中" || echo "已停止" ;;
    *) echo "未知" ;;
  esac
}

install_core() {
  need_root
  install_pkgs
  mkdir -p "$DIR" "$CERT_DIR" "$LOG_DIR"
  [ -f "$DB" ] || : > "$DB"
  chmod 600 "$DB"
  write_runtime_defaults
  url="$(latest_url)"
  tmp="/tmp/mihomo.$$.gz"
  out="/tmp/mihomo.$$"
  info "下载 Mihomo..."
  curl -fL --connect-timeout 10 --max-time 180 "$url" -o "$tmp"
  gzip -dc "$tmp" > "$out" || { rm -f "$tmp" "$out"; err "Mihomo 解压失败"; exit 1; }
  chmod 755 "$out"
  "$out" -v >/dev/null 2>&1 || { rm -f "$tmp" "$out"; err "Mihomo 核心无法运行"; exit 1; }
  mv "$out" "$BIN"
  rm -f "$tmp"
  render_config || exit 1
  write_service
  restart_service || exit 1
  ok "Mihomo 已安装/更新"
}

ensure_core() {
  [ -x "$BIN" ] && [ -f "$CONF" ] || install_core
}

new_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid; else openssl rand -hex 16; fi
}

rand_password() { openssl rand -hex 16; }
rand_shortid() { openssl rand -hex 8; }
base64_urlsafe() { base64 | tr '+/' '-_' | tr -d '=\n'; }

reality_keypair() {
  f="/tmp/reality-key.$$"
  openssl genpkey -algorithm X25519 -out "$f" >/dev/null 2>&1
  priv="$(openssl pkey -in "$f" -outform DER 2>/dev/null | tail -c 32 | base64_urlsafe)"
  pub="$(openssl pkey -in "$f" -pubout -outform DER 2>/dev/null | tail -c 32 | base64_urlsafe)"
  rm -f "$f"
  [ -n "$priv" ] && [ -n "$pub" ] || return 1
  printf '%s|%s' "$priv" "$pub"
}

safe_name() { printf '%s' "$1" | tr '|,\r\n' '----'; }
yaml_sq() { printf '%s' "$1" | sed "s/'/''/g"; }
url_name() { printf '%s' "$1" | sed 's/%/%25/g; s/ /%20/g; s/#/%23/g'; }

valid_port() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

port_used() {
  [ -s "$DB" ] || return 1
  awk -F'|' -v p="$1" '$3 == p { found=1 } END { exit found ? 0 : 1 }' "$DB"
}

name_used() {
  [ -s "$DB" ] || return 1
  awk -F'|' -v n="$1" '$2 == n { found=1 } END { exit found ? 0 : 1 }' "$DB"
}

public_ip() {
  ip="$(curl -4fsS --connect-timeout 4 https://api.ipify.org 2>/dev/null || true)"
  [ -n "$ip" ] || ip="$(curl -4fsS --connect-timeout 4 https://ifconfig.me 2>/dev/null || true)"
  [ -n "$ip" ] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "$ip"
}

cert_for() {
  id="$1"; sni="$2"
  cert="$CERT_DIR/$id.crt"; key="$CERT_DIR/$id.key"
  if [ ! -s "$cert" ] || [ ! -s "$key" ]; then
    if ! openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -sha256 -days 3650 -subj "/CN=$sni" -addext "subjectAltName=DNS:$sni" -keyout "$key" -out "$cert" >/dev/null 2>&1; then
      openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -sha256 -days 3650 -subj "/CN=$sni" -keyout "$key" -out "$cert" >/dev/null 2>&1
    fi
    chmod 600 "$cert" "$key"
  fi
  printf '%s|%s' "$cert" "$key"
}

render_config() {
  mkdir -p "$DIR" "$CERT_DIR"
  [ -f "$DB" ] || : > "$DB"
  tmp="$CONF.tmp.$$"
  cat > "$tmp" <<'EOF_HEAD'
mode: rule
log-level: warning
ipv6: false
find-process-mode: off
geodata-loader: memconservative
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
EOF_HEAD
  if [ -s "$DB" ]; then printf 'listeners:\n' >> "$tmp"; else printf 'listeners: []\n' >> "$tmp"; fi

  while IFS='|' read -r proto name port cred sni a b c d; do
    [ -n "${proto:-}" ] || continue
    qn="$(yaml_sq "$name")"; qs="$(yaml_sq "$sni")"; qc="$(yaml_sq "$cred")"
    case "$proto" in
      anytls)
        cert="$a"; key="$b"
        cat >> "$tmp" <<EOF_ANY
  - name: '$qn'
    type: anytls
    port: $port
    listen: 0.0.0.0
    users:
      default: '$qc'
    certificate: '$cert'
    private-key: '$key'
EOF_ANY
        ;;
      hysteria2)
        cert="$a"; key="$b"; obfs="$c"
        cat >> "$tmp" <<EOF_HY
  - name: '$qn'
    type: hysteria2
    port: $port
    listen: 0.0.0.0
    users:
      default: '$qc'
    up: 10000
    down: 10000
    ignore-client-bandwidth: false
    certificate: '$cert'
    private-key: '$key'
    alpn:
      - h3
EOF_HY
        if [ -n "$obfs" ]; then
          qo="$(yaml_sq "$obfs")"
          cat >> "$tmp" <<EOF_OBFS
    obfs: salamander
    obfs-password: '$qo'
EOF_OBFS
        fi
        ;;
      reality)
        priv="$a"; pub="$b"; sid="$c"
        cat >> "$tmp" <<EOF_REAL
  - name: '$qn'
    type: vless
    port: $port
    listen: 0.0.0.0
    users:
      - username: default
        uuid: '$qc'
        flow: xtls-rprx-vision
    reality-config:
      dest: '$qs:443'
      private-key: '$priv'
      short-id:
        - '$sid'
      server-names:
        - '$qs'
EOF_REAL
        ;;
    esac
  done < "$DB"

  load_runtime
  if [ -x "$BIN" ]; then
    if ! "$BIN" -t -d "$DIR" -f "$tmp" >/tmp/mihomo-check.$$ 2>&1; then
      cat /tmp/mihomo-check.$$ >&2
      rm -f /tmp/mihomo-check.$$ "$tmp"
      err "Mihomo 配置校验失败"
      return 1
    fi
    rm -f /tmp/mihomo-check.$$
  fi
  mv "$tmp" "$CONF"
  chmod 600 "$CONF"
}

append_node() {
  line="$1"
  cp "$DB" "$DB.bak.$$" 2>/dev/null || : > "$DB.bak.$$"
  printf '%s\n' "$line" >> "$DB"
  if ! render_config; then
    mv "$DB.bak.$$" "$DB"
    render_config >/dev/null 2>&1 || true
    return 1
  fi
  rm -f "$DB.bak.$$"
  restart_service
}

show_line() {
  proto="$1"; name="$2"; port="$3"; cred="$4"; sni="$5"; a="$6"; b="$7"; c="$8"; d="${9:-}"
  ip="$(public_ip)"
  case "$ip" in *:*) host="[$ip]" ;; *) host="$ip" ;; esac
  case "$proto" in
    anytls) printf '%s = anytls, %s, %s, password=%s, sni=%s, skip-cert-verify=true, tfo=true, udp-relay=true\n' "$name" "$host" "$port" "$cred" "$sni" ;;
    hysteria2)
      printf '%s = hysteria2, %s, %s, password=%s, sni=%s, alpn=h3, skip-cert-verify=true, download-bandwidth=10000' "$name" "$host" "$port" "$cred" "$sni"
      [ -n "$c" ] && printf ', salamander-password=%s' "$c"
      printf '\n'
      ;;
    reality) printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&flow=xtls-rprx-vision#%s\n' "$cred" "$host" "$port" "$sni" "$b" "$c" "$(url_name "$name")" ;;
  esac
}

show_nodes() {
  [ -s "$DB" ] || { info "暂无节点"; return; }
  while IFS='|' read -r proto name port cred sni a b c d; do
    [ -n "${proto:-}" ] || continue
    show_line "$proto" "$name" "$port" "$cred" "$sni" "$a" "$b" "$c" "$d"
  done < "$DB"
}

prompt_value() {
  label="$1"; def="$2"
  printf '%s [%s]: ' "$label" "$def" >&2
  IFS= read -r v || v=""
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$def"
}

add_anytls() {
  ensure_core
  name="$(safe_name "$(prompt_value '节点名' 'AnyTLS-61368')")"; port="$(prompt_value '端口' '61368')"; sni="$(prompt_value 'SNI' "$DEFAULT_SNI")"
  valid_port "$port" || { err "端口无效"; return 1; }; port_used "$port" && { err "端口已被本脚本中的节点使用"; return 1; }; name_used "$name" && { err "节点名已存在"; return 1; }
  pass="$(rand_password)"; pair="$(cert_for "anytls-$port" "$sni")"; cert="${pair%%|*}"; key="${pair#*|}"
  append_node "anytls|$name|$port|$pass|$sni|$cert|$key||" || return 1
  ok "AnyTLS 已创建"; show_line anytls "$name" "$port" "$pass" "$sni" "$cert" "$key" "" ""
}

add_hy2() {
  ensure_core
  name="$(safe_name "$(prompt_value '节点名' 'Hysteria2-62368')")"; port="$(prompt_value '端口' '62368')"; sni="$(prompt_value 'SNI' "$DEFAULT_SNI")"
  printf '启用 Salamander 混淆? [y/N]: ' >&2; IFS= read -r yn || yn=""; obfs=""; case "$yn" in y|Y) obfs="$(rand_password)" ;; esac
  valid_port "$port" || { err "端口无效"; return 1; }; port_used "$port" && { err "端口已被本脚本中的节点使用"; return 1; }; name_used "$name" && { err "节点名已存在"; return 1; }
  pass="$(rand_password)"; pair="$(cert_for "hy2-$port" "$sni")"; cert="${pair%%|*}"; key="${pair#*|}"
  append_node "hysteria2|$name|$port|$pass|$sni|$cert|$key|$obfs|" || return 1
  ok "Hysteria2 已创建"; show_line hysteria2 "$name" "$port" "$pass" "$sni" "$cert" "$key" "$obfs" ""
}

add_reality() {
  ensure_core
  name="$(safe_name "$(prompt_value '节点名' 'Reality-63368')")"; port="$(prompt_value '端口' '63368')"; sni="$(prompt_value 'SNI/目标域名' "$DEFAULT_SNI")"
  valid_port "$port" || { err "端口无效"; return 1; }; port_used "$port" && { err "端口已被本脚本中的节点使用"; return 1; }; name_used "$name" && { err "节点名已存在"; return 1; }
  uuid="$(new_uuid)"; sid="$(rand_shortid)"; kp="$(reality_keypair)" || { err "Reality 密钥生成失败"; return 1; }; priv="${kp%%|*}"; pub="${kp#*|}"
  append_node "reality|$name|$port|$uuid|$sni|$priv|$pub|$sid|" || return 1
  ok "VLESS Reality 已创建；Surge 不原生支持 VLESS，下面保留 URI"; show_line reality "$name" "$port" "$uuid" "$sni" "$priv" "$pub" "$sid" ""
}

auto_add_one() {
  proto="$1"; name="$2"; port="$3"; sni="$4"
  if name_used "$name" || port_used "$port"; then return 0; fi
  case "$proto" in
    anytls) pass="$(rand_password)"; pair="$(cert_for "anytls-$port" "$sni")"; cert="${pair%%|*}"; key="${pair#*|}"; append_node "anytls|$name|$port|$pass|$sni|$cert|$key||" ;;
    hysteria2) pass="$(rand_password)"; pair="$(cert_for "hy2-$port" "$sni")"; cert="${pair%%|*}"; key="${pair#*|}"; append_node "hysteria2|$name|$port|$pass|$sni|$cert|$key||" ;;
    reality) uuid="$(new_uuid)"; sid="$(rand_shortid)"; kp="$(reality_keypair)" || return 1; priv="${kp%%|*}"; pub="${kp#*|}"; append_node "reality|$name|$port|$uuid|$sni|$priv|$pub|$sid|" ;;
  esac
}

auto_create() {
  ensure_core
  auto_add_one anytls "AnyTLS-61368" 61368 "$DEFAULT_SNI" || return 1
  auto_add_one hysteria2 "Hysteria2-62368" 62368 "$DEFAULT_SNI" || return 1
  auto_add_one reality "Reality-63368" 63368 "$DEFAULT_SNI" || return 1
  show_nodes
}

delete_node() {
  [ -s "$DB" ] || { info "暂无节点"; return; }
  awk -F'|' '{printf "%d) %s [%s:%s]\n", NR, $2, $1, $3}' "$DB"
  printf '输入要删除的序号: '; IFS= read -r n || n=""; case "$n" in ''|*[!0-9]*) err "序号无效"; return 1 ;; esac
  tmp="$DB.tmp.$$"; awk -v n="$n" 'NR != n {print}' "$DB" > "$tmp"
  [ "$(wc -l < "$tmp")" -lt "$(wc -l < "$DB")" ] || { rm -f "$tmp"; err "序号不存在"; return 1; }
  mv "$tmp" "$DB"; render_config || return 1; restart_service || return 1; ok "节点已删除"
}

runtime_show() {
  write_runtime_defaults
  m="$(mem_limit_mib 2>/dev/null || echo unknown)"
  say "检测内存限制: ${m} MiB"
  cat "$RUNTIME"
}

menu() {
  while true; do
    printf '\033[2J\033[H' 2>/dev/null || true
    say "========================================"
    say " Mihomo Surge Lite  $VERSION"
    say " 状态: $(status_text)"
    say "========================================"
    say " 1) 添加 AnyTLS"
    say " 2) 添加 Hysteria2"
    say " 3) 添加 VLESS Reality"
    say " 4) 查看节点"
    say " 5) 删除节点"
    say " 6) 重启服务"
    say " 7) 安装/更新 Mihomo 核心"
    say " 8) 查看低内存运行参数"
    say "22) 一键创建三个默认节点"
    say " 0) 退出"
    say "========================================"
    printf '请选择: '; IFS= read -r c || exit 0
    case "$c" in
      1) add_anytls || true ;;
      2) add_hy2 || true ;;
      3) add_reality || true ;;
      4) show_nodes ;;
      5) delete_node || true ;;
      6) ensure_core; restart_service && ok "已重启" ;;
      7) install_core ;;
      8) runtime_show ;;
      22) auto_create || true ;;
      0) exit 0 ;;
      *) err "无效选项" ;;
    esac
    printf '\n按回车返回菜单...'; IFS= read -r _ || exit 0
  done
}

install_self() {
  need_root
  src="$0"
  case "$src" in sh|bash|dash|-|/bin/sh|/bin/bash|/usr/bin/sh|/usr/bin/bash) return 0 ;; esac
  if [ "$src" != "$SELF" ] && [ -f "$src" ]; then cp "$src" "$SELF"; chmod 755 "$SELF"; fi
}

main() {
  need_root
  install_self
  mkdir -p "$DIR" "$CERT_DIR" "$LOG_DIR"
  [ -f "$DB" ] || : > "$DB"
  case "${1:-}" in
    install|update) install_core ;;
    auto) auto_create ;;
    show) show_nodes ;;
    restart) ensure_core; restart_service ;;
    runtime) runtime_show ;;
    '') menu ;;
    *) err "用法: mh [install|auto|show|restart|runtime]"; exit 1 ;;
  esac
}

main "$@"
