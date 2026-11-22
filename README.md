# Lain42 Node Deploy · 一键节点部署、极限调优与自动接入

面向 **lain42.top** 与 **dev.lain42.top** 的海外代理 VPS 一键部署、Linux 内核极限调优（BBR + fq + 64MB Socket 缓冲 + TFO）与自动接入工具集，内置中国大陆高速镜像加速（`https://sh.lain42.top`），解决大陆访问 GitHub Raw/Release 不稳定的痛点。

- **上游 Fork**：[lilyco-42/sing-box-yg](https://github.com/lilyco-42/sing-box-yg)（fork 自 `yonggekkk/sing-box-yg`）
- **大陆加速入口**：`https://sh.lain42.top`

## 1. 在新 VPS 上一键部署并极限调优

```bash
# 方式 A：推荐！一键无交互部署四协议（VLESS Reality + VMess WS + Hysteria2 + TUIC v5）+ 内核 BBR 极限调优
curl -fsSL https://sh.lain42.top | bash

# 指定地区标签与自定义端口
curl -fsSL https://sh.lain42.top | bash -s -- --region "🇯🇵 日本 · 东京" --vless-port 443

# 方式 B：通过大陆加速镜像直接启动 fork 后的 sing-box-yg 完整交互菜单
curl -fsSL https://sh.lain42.top/sb.sh | bash
# 或
curl -fsSL https://sh.lain42.top | bash -s -- --yg
```

部署完成后，会在 VPS 上生成标准接入清单：`/etc/s-box/lain42-nodes.json`。

## 2. 一键接入 `lain42.top` & `dev.lain42.top`

在本地控制机执行：

```bash
./join-lain42.sh root@<新VPS的IP>

# 如果目标 VPS 所在机房直连大陆受阻，可自动或手动指定高速跳板（dialer-proxy）
./join-lain42.sh root@<新VPS的IP> "🇰🇷 韩国 · VLESS"
```

`join-lain42.sh` 会自动完成：
1. 拉取目标 VPS 的 `/etc/s-box/lain42-nodes.json`；
2. 探测国内主站直连连通性，若 TCP 受阻自动挂载 `dialer-proxy` 链式跳板；
3. 合并写入 `lain42.top:/opt/studio-billing/proxy-extras.json` 并执行真实 HTTPS 探活与 4MB 吞吐测速；
4. 同步写入 `dev.lain42.top`（`apps/lain42-portal/data/extra_nodes.json`）并自动重启服务生效。

## 3. 内核调优清单（`install.sh` 自动写入 `/etc/sysctl.d/99-lain42-proxy-tune.conf`）

- 拥塞控制：`net.core.default_qdisc = fq` + `net.ipv4.tcp_congestion_control = bbr`
- 连接提速：`tcp_fastopen = 3`、`tcp_slow_start_after_idle = 0`、`tcp_mtu_probing = 1`
- 高并发大缓冲：`rmem_max / wmem_max = 64MB`、`somaxconn = 32768`、`LimitNOFILE = 1048576`
- 协议规范：自动修正 VMess WebSocket `path` 前导 `/`，启用 `xtls-rprx-vision` 与 TUIC `zero_rtt_handshake` + `bbr`
