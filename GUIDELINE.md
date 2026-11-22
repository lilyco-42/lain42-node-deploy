# Lain42 节点部署与运维完整指南（GUIDELINE）

本指南面向两类读者：
1. **普通订阅用户**：如何在 Windows / macOS / Linux / iOS / Android 上导入并使用 `lain42.top` 订阅；
2. **节点运维与开发者**：如何使用 `https://sh.lain42.top`（中国大陆高速加速镜像）在任意 VPS 上一键部署、调优并接入 `lain42.top` 与 `dev.lain42.top`。

---

## 一、普通用户快速上手（三步连通）

### 1. 套餐选择（15 元 vs 30 元月卡）
| 套餐名称 | 价格 / 积分 | 流量配额 | 有效期 | 适用场景 |
| :--- | :--- | :--- | :--- | :--- |
| **轻量月卡** (`proxy_1m`) | ¥15（150 积分） | **100 GB** | 30 天 | 日常查资料、AI 对话、轻度流媒体 |
| **标准月卡** (`proxy_1m_220g`) | ¥30（300 积分） | **220 GB**（多送 20GB） | 30 天 | 高频开发、4K 视频、GitHub 大文件拉取 |
| **季卡（98 折）** (`proxy_3m`) | ¥88.2（882 积分） | **660 GB** | 90 天 | 长期稳定开发与学习 |
| **年卡（9 折）** (`proxy_1y`) | ¥324（3240 积分） | **2640 GB** | 365 天 | 全年主力工作流，立省 ¥36 |

> **计费说明**：代理专线属于不可复制高价值资源，仅支持使用**充值付费积分**购买（免费赠送/签到积分仅限购买软件工具与可复制资源）。

### 2. 全平台客户端导入教程

| 平台 | 推荐客户端 | 导入格式与步骤 |
| :--- | :--- | :--- |
| **Windows / macOS / Linux** | **Clash Verge Rev**（可在 `dev.lain42.top/downloads/clash-verge-rev` 夸克高速下载） | 1. 登录 `lain42.top/account/` 复制 **Clash 订阅链接**<br>2. 打开 Clash Verge → **订阅** → 粘贴链接并点击 **导入**<br>3. 点击 **代理** → `PROXY` 保持默认选择 **`🆕 自建专线 · 自动测速`**<br>4. 点击 **设置** → 开启 **系统代理**（终端/游戏可开启 **TUN 模式**） |
| **iOS (iPhone / iPad)** | **Karing** / **Shadowrocket** | 1. 复制 **Karing / 通用订阅链接**<br>2. 添加配置 → 粘贴 URL → 更新 → 连接 |
| **Android** | **FlClash** / **Clash Meta for Android** | 1. 复制 **Clash 订阅链接**<br>2. 配置 → 从 URL 导入 → 启动代理 |

### 3. 路由与自动选路说明
- **`🆕 自建专线 · 自动测速`**（推荐默认）：服务端每小时对全部自有节点执行 4MB 真实下载吞吐测速，仅将高吞吐节点（`>= 600 kbps`，当前覆盖韩国双专线、澳大利亚悉尼、德国法兰克福、美国西雅图、菲律宾马尼拉，峰值 4.7 MB/s）编入 `url-test` 组，客户端每 **120 秒**自动切换延迟最低的最优线路。
- **`🏫 校园网友好 · 443/TCP`**：当校园网/酒店屏蔽 UDP 或高位端口时，手动切至此组。
- **流量余量查看**：Clash Verge / Karing 订阅卡片会自动显示 `Subscription-Userinfo` 实时已用流量、总配额（100GB / 220GB）与到期时间。

---

## 二、运维与开发者：一键部署新 VPS 并接入线路池

### 1. 环境准备
- 一台全新的海外 Linux VPS（推荐 Ubuntu 22.04/24.04 或 Debian 12，架构支持 `amd64` / `arm64`）。
- 需具有 `root` 权限；安全组/云防火墙放行端口：`443/tcp`（VLESS Reality）、`2052/tcp`（VMess WS）、`51466/udp`（Hysteria2）、`24062/udp`（TUIC v5）。

### 2. 一键部署与内核极限调优（走大陆加速 `sh.lain42.top`）
直接 SSH 登录目标 VPS 执行：

```bash
# 全自动无人值守部署 + BBR/fq/64MB 缓冲调优 + 四协议启动
curl -fsSL https://sh.lain42.top | bash

# 如需自定义地区标签与端口：
curl -fsSL https://sh.lain42.top | bash -s -- \
  --region "🇯🇵 日本 · 东京" \
  --vless-port 443 \
  --vmess-port 2052 \
  --hy2-port 51466 \
  --tuic-port 24062
```

如需交互式管理（查看/修改节点、WARP 分流、卸载等），可直接通过大陆加速镜像拉起 fork 后的 `lilyco-42/sing-box-yg`：

```bash
curl -fsSL https://sh.lain42.top/sb.sh | bash
```

### 3. 一键接入 `lain42.top` 与 `dev.lain42.top`
在拥有 SSH 免密权限的控制机执行：

```bash
curl -fsSL https://sh.lain42.top/join-lain42.sh | bash -s -- root@<新VPS的IP>
```

**自动化接入流程说明**：
1. 自动从新 VPS 拉取 `/etc/s-box/lain42-nodes.json`；
2. 从国内主站实测到新 VPS 的 TCP 连通性：**若直连受阻，自动挂载 `dialer-proxy` 高速跳板中转**（也可传第 2 个参数手动指定跳板名）；
3. 合并写入 `lain42.top:/opt/studio-billing/proxy-extras.json`，立即执行 `lyco-official-health.py`（真实 HTTPS 探活）与 `lyco-throughput-audit.py`（4MB 吞吐测速）并重启 `studio-billing`；
4. 同步写入 `dev.lain42.top` 节点清单，所有订阅用户在下次刷新时即自动获得新线路。

### 4. 常见问题排查（Troubleshooting）
| 现象 | 排查命令 / 解决方法 |
| :--- | :--- |
| **新节点测速不通过 (`HTTPS_FAIL`)** | 检查云厂商控制台安全组是否放行对应 TCP/UDP 端口；若高端口被拦截，改用 `443` / `12360` / `32549`，或执行 `./join-lain42.sh root@<IP> "🇰🇷 韩国 · VLESS"` 走跳板。 |
| **客户端提示 `path` 或 WebSocket 握手失败** | 确保 `ws-opts.path` 带有前导 `/`（本仓库 `install.sh` 已默认规范输出 `/<uuid>-vm`）。 |
| **客户端无法更新订阅 / 节点显示旧流量** | 确认在 `lain42.top/account/` 续费后点击一次「更新订阅」；系统已支持老订阅 Token 自动映射至最新有效订单。 |
| **国内服务器拉取 GitHub 脚本超时** | 统一将 `raw.githubusercontent.com` 替换为大陆加速域名 `https://sh.lain42.top/`。 |
