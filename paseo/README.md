# Paseo

Paseo Docker 镜像，基于官方 [ghcr.io/getpaseo/paseo](https://github.com/getpaseo/paseo) 构建，继承其所有内置功能。

镜像包含 `install.sh` 脚本，支持按需安装 Agent CLI 和编程语言运行环境（参考 OpenCode 子项目的 on-demand 设计）。

## Build

镜像由 CI (`.github/workflows/paseo.yml`) 自动构建多架构 (amd64/arm64) 并推送：

```
ghcr.io/nuln/paseo:latest
ghcr.io/nuln/paseo:<version>
```

版本号从官方 GitHub release 自动获取。

## Usage

```bash
cd paseo
cp .env.sample .env  # 填写 PASEO_PASSWORD
docker compose up -d
```

- Web / API: `http://<hostIP>:6767`

## Install Agent CLI on demand

镜像不预装任何 Agent CLI，通过 `install.sh` 按需安装：

```bash
# 安装指定 Agent
docker exec paseo install.sh claude-code
docker exec paseo install.sh codex
docker exec paseo install.sh opencode

# 安装多个 Agent（空格分隔）
docker exec paseo install.sh claude-code codex opencode

# 升级到最新版本
docker exec paseo install.sh claude-code --update
docker exec paseo install.sh codex opencode --update
```

## Install coding environments on demand

Agent 运行时可能需要编译/运行代码，按需安装语言运行环境：

```bash
# 安装 Go
docker exec paseo install.sh go

# 安装多个
docker exec paseo install.sh go rust java

# 全部已安装工具在容器重启后依然可用（挂载 data/cache 持久化）
```

完整支持列表: `go` / `rust` / `java` / `bun` / `scala` / `kotlin` / `node-tools` / `lua` / `php`

## Volumes

| Host path | Container path | Description |
|-----------|---------------|-------------|
| `./data/home` | `/home/paseo` | Paseo home (configs, state) |
| `./data/config` | `/etc/paseo` | Server config |
| `./workspace` | `/workspace` | Code workspace |

## Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PASEO_PASSWORD` | Auth password | — |
| `PASEO_LISTEN` | Listen address | `0.0.0.0:6767` |
| `PASEO_LOG_LEVEL` | Log level | `info` |
| `PASEO_WEB_UI_ENABLED` | Enable Web UI | `true` |
| `MEM_LIMIT` | Container memory cap | `2g` |
| `CPU_LIMIT` | Container CPU limit | `2` |

## Relay（自建中继）

Paseo 官方推荐使用中继连接移动端 App，所有流量端到端加密（Curve25519 ECDH + XSalsa20-Poly1305）。

`relay/` 目录提供自建中继的配置模板，基于 [paseo-relay](https://github.com/zenghongtu/paseo-relay)（轻量 Go 中继服务）。

### 启动中继

```bash
cd paseo/relay
cp .env.sample .env
docker compose up -d
```

中继监听 `0.0.0.0:8411`。

### 配置 Caddy 反代（公网访问）

编辑 `relay/Caddyfile`，将 `relay.example.com` 替换为你的域名，然后部署 Caddy：

```bash
caddy run --config relay/Caddyfile
```

### 配置 Paseo daemon 连接自建中继

将 `relay/config.json` 复制到 paseo 容器的 `~/.paseo/config.json`（即挂载的 `./data/home/.paseo/config.json`），修改 `endpoint` 和 `publicEndpoint` 为你的中继地址：

```json
{
  "daemon": {
    "relay": {
      "enabled": true,
      "endpoint": "relay.example.com:443",
      "publicEndpoint": "relay.example.com:443"
    }
  }
}
```

然后重启 paseo 容器：

```bash
docker compose restart paseo
```

验证中继连接成功（容器日志中出现 `relay_control_connected` 即表示连接成功）。

### 访问方式总结

| 方式 | 适用场景 | 配置要点 |
|------|---------|---------|
| 局域网直连 | 同一 Wi-Fi | 客户端添加 `http://<宿主机IP>:6767` |
| Tailscale VPN | 多设备私网 | daemon 绑定 Tailscale IP，客户端用该 IP 连接 |
| 自建中继 | 手机 App 远程访问（推荐） | 启动 relay + Caddy，daemon 配置 relay endpoint |
| 公网反代 | 浏览器远程访问 | Caddy 反代 paseo:6767，设 `PASEO_HOSTNAMES` |

