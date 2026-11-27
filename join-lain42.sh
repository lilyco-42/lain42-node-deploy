#!/usr/bin/env bash
# ==============================================================================
# Lain42 节点一键接入脚本 (自动拉取 VPS 的 /etc/s-box/lain42-nodes.json 并接入
# lain42.top 生产线路池 + dev.lain42.top 新门户，支持自动探测直连/跳板中转)
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[join-lain42]${NC} $*"; }
ok()    { echo -e "${GREEN}[    OK    ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[   WARN   ]${NC} $*"; }
err()   { echo -e "${RED}[   FAIL   ]${NC} $*" >&2; exit 1; }

TARGET_HOST="${1:-}"
DIALER_PROXY="${2:-}"
LAIN42_SSH="${LAIN42_SSH:-lain42-ip}"

if [[ -z "$TARGET_HOST" ]]; then
  cat <<'EOF'
用法:
  ./join-lain42.sh <ssh_host_or_user@ip> [可选_dialer_proxy_节点名]

示例:
  ./join-lain42.sh root@1.2.3.4
  ./join-lain42.sh root@1.2.3.4 "🇰🇷 韩国 · VLESS"
EOF
  exit 1
fi

TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

info "正在从 ${TARGET_HOST} 拉取 /etc/s-box/lain42-nodes.json ..."
ssh -o StrictHostKeyChecking=no "$TARGET_HOST" "cat /etc/s-box/lain42-nodes.json" > "$TMP_JSON"
jq empty "$TMP_JSON" || err "拉取的 JSON 无效，请先在目标 VPS 上运行 curl -fsSL https://sh.lain42.top | bash"

COUNT="$(jq 'length' "$TMP_JSON")"
SERVER_IP="$(jq -r '.[0].server' "$TMP_JSON")"
ok "已获取 ${COUNT} 个节点定义 (server=${SERVER_IP})"

# 上传并合并到 lain42.top:/opt/studio-billing/proxy-extras.json
info "正在合并到 ${LAIN42_SSH}:/opt/studio-billing/proxy-extras.json 并触发实测健康/吞吐审核..."
ssh -o StrictHostKeyChecking=no "$LAIN42_SSH" "DIALER_PROXY='${DIALER_PROXY}' python3 -c \"
import json, os, shutil, socket, sys, time
from pathlib import Path

new_nodes = json.loads(sys.stdin.read())
dialer = os.environ.get('DIALER_PROXY', '').strip()

extras_path = Path('/opt/studio-billing/proxy-extras.json')
shutil.copy2(extras_path, f'/opt/studio-billing/proxy-extras.json.bak-join-{int(time.time())}')
existing = json.loads(extras_path.read_text(encoding='utf-8'))

def tcp_open(ip, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1.8)
    try:
        s.connect((ip, int(port)))
        return True
    except Exception:
        return False
    finally:
        s.close()

for n in new_nodes:
    if n.get('type') in ('vless', 'vmess', 'anytls'):
        if dialer:
            n['dialer-proxy'] = dialer
        elif not tcp_open(n['server'], n['port']):
            n['dialer-proxy'] = '🇰🇷 韩国 · VLESS'
            print(f'  [auto-relay] {n[chr(110)+chr(97)+chr(109)+chr(101)]} TCP 直连受阻，自动挂载跳板: 🇰🇷 韩国 · VLESS')

new_keys = {(n['server'], n['type']) for n in new_nodes}
merged = [x for x in existing if (x.get('server'), x.get('type')) not in new_keys] + new_nodes
extras_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'Merged {len(new_nodes)} nodes into proxy-extras.json (total={len(merged)})')
\"" < "$TMP_JSON"

info "正在主站运行真实 HTTPS 探活与 4MB 吞吐测速..."
ssh -o StrictHostKeyChecking=no "$LAIN42_SSH" "
  python3 /opt/studio-billing/lyco-official-health.py
  python3 /opt/studio-billing/lyco-throughput-audit.py
  systemctl restart studio-billing
  sleep 1
  systemctl is-active studio-billing
"
ok "已成功接入 lain42.top 生产线路池并生效！"

# 同步备份 JSON 片段到本机 dev.lain42.top 数据目录 (供 lain42-portal 订阅模板引用)
PORTAL_NODES_FILE="/home/lilyco/code/lilyco/apps/lain42-portal/data/extra_nodes.json"
if [[ -d "$(dirname "$PORTAL_NODES_FILE")" ]]; then
  python3 - "$TMP_JSON" "$PORTAL_NODES_FILE" << 'PY'
import json, sys
from pathlib import Path
new_nodes = json.loads(Path(sys.argv[1]).read_text())
dst = Path(sys.argv[2])
cur = json.loads(dst.read_text()) if dst.exists() else []
keys = {(n["server"], n["type"]) for n in new_nodes}
merged = [x for x in cur if (x.get("server"), x.get("type")) not in keys] + new_nodes
dst.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n")
print(f"Synced {len(new_nodes)} nodes to {dst} (total={len(merged)})")
PY
  ok "已同步写入 dev.lain42.top 门户节点清单: ${PORTAL_NODES_FILE}"
fi
