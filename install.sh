#!/usr/bin/env bash
# ==============================================================================
# Lain42 一键节点部署、内核极限调优与自动接入脚本
# Upstream fork: https://github.com/lilyco-42/sing-box-yg
# Repo:          https://github.com/lilyco-42/lain42-node-deploy
# Mainland CDN:  curl -fsSL https://sh.lain42.top | bash
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[lain42]${NC} $*"; }
ok()    { echo -e "${GREEN}[  OK  ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
err()   { echo -e "${RED}[ FAIL ]${NC} $*" >&2; exit 1; }

# 默认配置（支持环境变量或 CLI 参数覆盖）
REGION="${LAIN42_REGION:-}"
NAME_PREFIX="${LAIN42_NAME:-}"
VLESS_PORT="${LAIN42_VLESS_PORT:-443}"
VMESS_PORT="${LAIN42_VMESS_PORT:-2052}"
HY2_PORT="${LAIN42_HY2_PORT:-51466}"
HY2_HOP_RANGE="${LAIN42_HY2_HOP:-20000-40000}"
TUIC_PORT="${LAIN42_TUIC_PORT:-24062}"
ANYTLS_PORT="${LAIN42_ANYTLS_PORT:-34657}"
SNI="${LAIN42_SNI:-apple.com}"
WS_HOST="${LAIN42_WS_HOST:-www.bing.com}"
UUID="${LAIN42_UUID:-}"
MIRROR_BASE="${LAIN42_MIRROR:-https://sh.lain42.top}"
SINGBOX_VERSION="${LAIN42_SINGBOX_VER:-1.12.0}"
REGISTER_URL="${LAIN42_REGISTER_URL:-}"
REGISTER_TOKEN="${LAIN42_REGISTER_TOKEN:-}"
USE_YG_MENU=0
SKIP_TUNE=0

usage() {
  cat <<'EOF'
Lain42 一键节点部署与调优脚本

用法:
  curl -fsSL https://sh.lain42.top | bash -s -- [选项]

选项:
  --region <标签>       地区标签，例如 "🇯🇵 日本 · 东京" / "🇰🇷 韩国 · 首尔" / "🇺🇸 美国 · 西雅图"
  --vless-port <端口>   VLESS Reality 监听端口 (默认: 443)
  --vmess-port <端口>   VMess WS 监听端口 (默认: 2052)
  --hy2-port <端口>     Hysteria2 监听端口 (默认: 51466)
  --tuic-port <端口>    TUIC v5 监听端口 (默认: 24062)
  --anytls-port <端口>  AnyTLS 监听端口 (默认: 34657)
  --sni <域名>          Reality 伪装域名 (默认: apple.com)
  --uuid <UUID>         指定共享 UUID (默认自动生成)
  --yg                  直接拉起 fork 后的 sing-box-yg 完整交互菜单 (加速镜像)
  --skip-tune           跳过内核 BBR/TCP/UDP 网络栈调优
  -h, --help            显示此帮助

示例:
  curl -fsSL https://sh.lain42.top | bash -s -- --region "🇯🇵 日本 · 东京"
  curl -fsSL https://sh.lain42.top | bash -s -- --yg
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)      REGION="$2"; shift 2 ;;
    --name)        NAME_PREFIX="$2"; shift 2 ;;
    --vless-port)  VLESS_PORT="$2"; shift 2 ;;
    --vmess-port)  VMESS_PORT="$2"; shift 2 ;;
    --hy2-port)    HY2_PORT="$2"; shift 2 ;;
    --tuic-port)   TUIC_PORT="$2"; shift 2 ;;
    --anytls-port) ANYTLS_PORT="$2"; shift 2 ;;
    --sni)         SNI="$2"; shift 2 ;;
    --uuid)        UUID="$2"; shift 2 ;;
    --yg)          USE_YG_MENU=1; shift ;;
    --skip-tune)   SKIP_TUNE=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             warn "忽略未知参数: $1"; shift ;;
  esac
done

[[ $EUID -eq 0 ]] || err "请使用 root 权限运行 (sudo bash)"

if [[ "$USE_YG_MENU" -eq 1 ]]; then
  info "正在通过大陆加速镜像启动 lilyco-42/sing-box-yg 交互脚本..."
  exec bash <(curl -fsSL "${MIRROR_BASE}/sb.sh")
fi

# 1. 基础依赖检查
install_deps() {
  local pkgs=(curl openssl jq tar gzip ca-certificates iproute2)
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq "${pkgs[@]}" >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q curl openssl jq tar gzip ca-certificates iproute >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q curl openssl jq tar gzip ca-certificates iproute >/dev/null 2>&1
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl openssl jq tar gzip ca-certificates iproute2 bash >/dev/null 2>&1
  fi
}

# 2. 内核网络栈极限调优 (BBR + fq + TCP/UDP 大缓冲区 + TFO + 文件描述符)
tune_kernel() {
  info "正在执行 Linux 内核网络栈调优 (BBR + fq + 64MB Socket Buffer + TFO)..."
  modprobe tcp_bbr 2>/dev/null || true
  cat > /etc/sysctl.d/99-lain42-proxy-tune.conf <<'EOF'
# Lain42 Proxy High-Throughput Kernel Tuning
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.optmem_max = 65536
net.core.netdev_max_backlog = 32768
net.core.somaxconn = 32768
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 131072 67108864
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_max_syn_backlog = 16384
fs.file-max = 1048576
EOF
  sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-lain42-proxy-tune.conf >/dev/null 2>&1 || true

  mkdir -p /etc/security/limits.d
  cat > /etc/security/limits.d/99-lain42-nofile.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
  ok "内核调优完成 (拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown))"
}

# 3. 下载并安装 sing-box (优先走 GitHub，失败自动回退 sh.lain42.top 加速镜像)
install_singbox() {
  local arch
  case "$(uname -m)" in
    x86_64|amd64)   arch="amd64" ;;
    aarch64|arm64)  arch="arm64" ;;
    *) err "不支持的 CPU 架构: $(uname -m)" ;;
  esac

  mkdir -p /etc/s-box
  if [[ -x /etc/s-box/sing-box ]]; then
    ok "检测到已有 /etc/s-box/sing-box: $(/etc/s-box/sing-box version | head -n1)"
    return
  fi

  local ver="${SINGBOX_VERSION}"
  local tgz="sing-box-${ver}-linux-${arch}.tar.gz"
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  local urls=(
    "${MIRROR_BASE}/bins/${tgz}"
    "https://github.com/SagerNet/sing-box/releases/download/v${ver}/${tgz}"
    "https://ghfast.top/https://github.com/SagerNet/sing-box/releases/download/v${ver}/${tgz}"
  )
  local downloaded=0
  for u in "${urls[@]}"; do
    info "尝试下载 sing-box v${ver} (${arch}): ${u}"
    if curl -fL --connect-timeout 8 --max-time 60 -o "${tmpdir}/${tgz}" "$u" 2>/dev/null; then
      downloaded=1
      break
    fi
  done
  [[ "$downloaded" -eq 1 ]] || err "sing-box 下载失败，请检查网络"

  tar -xzf "${tmpdir}/${tgz}" -C "${tmpdir}"
  install -m 0755 "${tmpdir}/sing-box-${ver}-linux-${arch}/sing-box" /etc/s-box/sing-box
  ln -sf /etc/s-box/sing-box /usr/local/bin/sing-box
  ok "sing-box 安装完成: $(/etc/s-box/sing-box version | head -n1)"
}

# 4. 生成自签证书 + Reality 密钥对 + 五协议 sing-box 配置
generate_config() {
  local pub_ip
  pub_ip="$(curl -4 -fsSL --max-time 6 https://api.ipify.org 2>/dev/null || curl -4 -fsSL --max-time 6 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
  [[ -n "$pub_ip" ]] || err "无法获取公网 IPv4 地址"

  # 自动识别地区
  if [[ -z "$REGION" ]]; then
    local cc city
    cc="$(curl -fsSL --max-time 5 "https://ipinfo.io/${pub_ip}/country" 2>/dev/null | tr -d '\r\n' || echo "XX")"
    city="$(curl -fsSL --max-time 5 "https://ipinfo.io/${pub_ip}/city" 2>/dev/null | tr -d '\r\n' || echo "Node")"
    case "$cc" in
      KR) REGION="🇰🇷 韩国 · ${city}" ;;
      JP) REGION="🇯🇵 日本 · ${city}" ;;
      US) REGION="🇺🇸 美国 · ${city}" ;;
      SG) REGION="🇸🇬 新加坡 · ${city}" ;;
      PH) REGION="🇵🇭 菲律宾 · ${city}" ;;
      AU) REGION="🇦🇺 澳大利亚 · ${city}" ;;
      DE) REGION="🇩🇪 德国 · ${city}" ;;
      HK) REGION="🇭🇰 香港 · ${city}" ;;
      TW) REGION="🇹🇼 台湾 · ${city}" ;;
      GB) REGION="🇬🇧 英国 · ${city}" ;;
      *)  REGION="🌐 ${cc} · ${city}" ;;
    esac
  fi
  [[ -n "$NAME_PREFIX" ]] || NAME_PREFIX="$REGION"

  # 生成或复用 UUID
  if [[ -z "$UUID" ]]; then
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
      UUID="$(cat /proc/sys/kernel/random/uuid)"
    else
      UUID="$(/etc/s-box/sing-box generate uuid)"
    fi
  fi

  # 生成 Reality 密钥对与 short_id
  local kp priv_key pub_key short_id
  kp="$(/etc/s-box/sing-box generate reality-keypair)"
  priv_key="$(echo "$kp" | awk '/PrivateKey/{print $2}')"
  pub_key="$(echo "$kp" | awk '/PublicKey/{print $2}')"
  short_id="$(openssl rand -hex 4)"

  # 生成自签 ECC 证书 (供 Hysteria2 / TUIC / AnyTLS 使用)
  openssl ecparam -genkey -name prime256v1 -out /etc/s-box/private.key 2>/dev/null
  openssl req -new -x509 -days 3650 -key /etc/s-box/private.key -out /etc/s-box/cert.pem -subj "/CN=${WS_HOST}" 2>/dev/null

  # 写入调优后的 /etc/s-box/sb.json (带前导 / 的标准 WS path + TFO + BBR)
  local ws_path="/${UUID}-vm"
  cat > /etc/s-box/sb.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${VLESS_PORT},
      "tcp_fast_open": true,
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SNI}",
            "server_port": 443
          },
          "private_key": "${priv_key}",
          "short_id": ["${short_id}"]
        }
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-sb",
      "listen": "::",
      "listen_port": ${VMESS_PORT},
      "tcp_fast_open": true,
      "users": [
        {
          "uuid": "${UUID}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${ws_path}",
        "max_early_data": 2048,
        "early_data_header_name": "Sec-WebSocket-Protocol"
      },
      "tls": {
        "enabled": false
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-sb",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [
        {
          "password": "${UUID}"
        }
      ],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/etc/s-box/cert.pem",
        "key_path": "/etc/s-box/private.key"
      }
    },
    {
      "type": "tuic",
      "tag": "tuic5-sb",
      "listen": "::",
      "listen_port": ${TUIC_PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "password": "${UUID}"
        }
      ],
      "congestion_control": "bbr",
      "zero_rtt_handshake": true,
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/etc/s-box/cert.pem",
        "key_path": "/etc/s-box/private.key"
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-sb",
      "listen": "::",
      "listen_port": ${ANYTLS_PORT},
      "tcp_fast_open": true,
      "users": [
        {
          "password": "${UUID}"
        }
      ],
      "padding_scheme": [
        "stop=8",
        "0=30-30",
        "1=100-400",
        "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000",
        "3=9-9,500-1000",
        "4=500-1000",
        "5=500-1000",
        "6=500-1000",
        "7=500-1000"
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/s-box/cert.pem",
        "key_path": "/etc/s-box/private.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF

  /etc/s-box/sing-box check -c /etc/s-box/sb.json || err "sing-box 配置校验失败"

  # 写入 systemd 服务 (高 LimitNOFILE + 自动重启)
  cat > /etc/systemd/system/sing-box.service <<'EOF'
[Unit]
Description=Lain42 Optimized sing-box Node Service
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
Restart=always
RestartSec=3
LimitNOFILE=1048576
LimitNPROC=65536
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now sing-box
  systemctl restart sing-box
  sleep 1
  systemctl is-active --quiet sing-box || err "sing-box 启动失败，请查看 journalctl -u sing-box"

  # 放行防火墙端口 (ufw) 并配置 Hysteria2 UDP 端口跳跃 (Port Hopping: 20000-40000 -> HY2_PORT)
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    for p in "$VLESS_PORT/tcp" "$VMESS_PORT/tcp" "$ANYTLS_PORT/tcp" "$HY2_PORT/udp" "$TUIC_PORT/udp"; do
      ufw allow "$p" >/dev/null 2>&1 || true
    done
    ufw allow "${HY2_HOP_RANGE//-/:}/udp" >/dev/null 2>&1 || true
  fi
  if command -v iptables >/dev/null 2>&1 && [[ -n "${HY2_HOP_RANGE}" ]]; then
    local hop_colon="${HY2_HOP_RANGE//-/:}"
    iptables -t nat -C PREROUTING -p udp --dport "${hop_colon}" -j DNAT --to-destination ":${HY2_PORT}" 2>/dev/null || \
      iptables -t nat -A PREROUTING -p udp --dport "${hop_colon}" -j DNAT --to-destination ":${HY2_PORT}" 2>/dev/null || true
    if command -v ip6tables >/dev/null 2>&1; then
      ip6tables -t nat -C PREROUTING -p udp --dport "${hop_colon}" -j DNAT --to-destination ":${HY2_PORT}" 2>/dev/null || \
        ip6tables -t nat -A PREROUTING -p udp --dport "${hop_colon}" -j DNAT --to-destination ":${HY2_PORT}" 2>/dev/null || true
    fi
    ok "Hysteria2 UDP 端口跳跃已启用: ${HY2_HOP_RANGE} -> ${HY2_PORT}"
  fi

  # 生成标准 Lain42 接入 JSON (可直接导入 lain42.top proxy-extras.json 与 dev.lain42.top)
  cat > /etc/s-box/lain42-nodes.json <<EOF
[
  {
    "name": "${NAME_PREFIX} · VLESS",
    "type": "vless",
    "server": "${pub_ip}",
    "port": ${VLESS_PORT},
    "uuid": "${UUID}",
    "tls": true,
    "network": "tcp",
    "servername": "${SNI}",
    "flow": "xtls-rprx-vision",
    "client-fingerprint": "chrome",
    "reality-opts": {
      "public-key": "${pub_key}",
      "short-id": "${short_id}"
    },
    "udp": true
  },
  {
    "name": "${NAME_PREFIX} · VMess",
    "type": "vmess",
    "server": "${pub_ip}",
    "port": ${VMESS_PORT},
    "uuid": "${UUID}",
    "alterId": 0,
    "cipher": "auto",
    "tls": false,
    "network": "ws",
    "ws-opts": {
      "path": "${ws_path}",
      "headers": {
        "Host": "${WS_HOST}"
      }
    },
    "udp": true
  },
  {
    "name": "${NAME_PREFIX} · Hysteria2",
    "type": "hysteria2",
    "server": "${pub_ip}",
    "port": ${HY2_PORT},
    "ports": "${HY2_HOP_RANGE}",
    "password": "${UUID}",
    "sni": "${WS_HOST}",
    "alpn": ["h3"],
    "skip-cert-verify": true,
    "udp": true
  },
  {
    "name": "${NAME_PREFIX} · TUIC",
    "type": "tuic",
    "server": "${pub_ip}",
    "port": ${TUIC_PORT},
    "uuid": "${UUID}",
    "password": "${UUID}",
    "sni": "${WS_HOST}",
    "alpn": ["h3"],
    "udp-relay-mode": "native",
    "congestion-controller": "bbr",
    "skip-cert-verify": true,
    "udp": true
  },
  {
    "name": "${NAME_PREFIX} · AnyTLS",
    "type": "anytls",
    "server": "${pub_ip}",
    "port": ${ANYTLS_PORT},
    "password": "${UUID}",
    "sni": "${WS_HOST}",
    "skip-cert-verify": true,
    "udp": true
  }
]
EOF

  ok "节点已部署并启动完成！"
  echo ""
  echo "================================================================"
  echo "  Lain42 节点接入信息已保存至: /etc/s-box/lain42-nodes.json"
  echo "  公网 IP:  ${pub_ip}"
  echo "  地区标签: ${NAME_PREFIX}"
  echo "  VLESS:    ${pub_ip}:${VLESS_PORT} (Reality, pbk=${pub_key}, sid=${short_id})"
  echo "  VMess:    ${pub_ip}:${VMESS_PORT} (WS, path=${ws_path})"
  echo "  Hy2:      ${pub_ip}:${HY2_PORT} (UDP/QUIC + 端口跳跃 ${HY2_HOP_RANGE})"
  echo "  TUIC v5:  ${pub_ip}:${TUIC_PORT} (UDP/BBR)"
  echo "  AnyTLS:   ${pub_ip}:${ANYTLS_PORT} (TLS 会话复用 + Padding)"
  echo "================================================================"
  echo ""
  echo "在控制机执行以下命令即可一键接入 lain42.top + dev.lain42.top："
  echo "  ./join-lain42.sh root@${pub_ip}"
}

main() {
  install_deps
  if [[ "$SKIP_TUNE" -eq 0 ]]; then
    tune_kernel
  fi
  install_singbox
  generate_config
}

main "$@"
