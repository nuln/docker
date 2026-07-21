# Lunel

基于官方 [lunel-dev/lunel](https://github.com/lunel-dev/lunel) 构建的 Docker 镜像，包含 WebSocket 中继（Proxy）和控制面（Manager）。

镜像包含 `install.sh` 脚本，支持按需安装 Lunel CLI 和 Agent CLI / 编程语言运行环境。

## 项目结构

| 模块 | 说明 |
|------|------|
| **Proxy** | WebSocket 中继/网关（Bun），负责 CLI 与手机 App 之间的消息转发 |
| **Manager** | 控制面（Bun + SQLite），负责 session 管理、密码校验、审计日志 |

## Build

Dockerfile 从 github.com/lunel-dev/lunel 克隆源码构建，无需外部依赖。

本地构建：

```bash
cd lunel
docker build -t lunel .
```

镜像由 CI (`.github/workflows/lunel.yml`) 自动构建多架构 (amd64/arm64) 并推送至 `ghcr.io/nuln/lunel:latest`。

## Usage

```bash
cd lunel
cp .env.sample .env    # 填写 MANAGER_ADMIN_PASSWORD、PROXY_PASSWORD、PUBLIC_URL
docker compose up -d
```

- Manager API: `http://localhost:8899`
- Proxy (中继): `http://localhost:3000`

## 连接流程

Lunel 的连接由 Manager 统一调度，CLI 和 App **不直接配置中继地址**，而是通过 Manager 分配：

```
CLI ──WebSocket──→ Manager (/v2/assemble)
App ──WebSocket──→ Manager (/v2/assemble)   ← 两端配对后获得 password
                      │
                      ▼
Manager 分配 Proxy URL（GET /v2/proxy?password=xxx）
                      │
                      ▼
CLI ──WS──→ Proxy ──WS── App    ← Manager 分配的 Proxy 进行消息中继
```

### 关键行为

- **CLI** 和 **App** 的 Proxy 地址均由 Manager 通过 `/v2/proxy` API 返回
- Proxy 启动时通过 `PUBLIC_URL` 向 Manager 注册自己
- Manager 用一致性哈希将 session 分配到不同的 Proxy

## Install Agent CLI on demand

```bash
# 安装 Lunel CLI
docker exec lunel-manager install.sh lunel-cli

# 安装 AI Agent（Lunel 支持的 AI 后端）
docker exec lunel-manager install.sh opencode
docker exec lunel-manager install.sh codex
docker exec lunel-manager install.sh pi

# 升级到最新版本
docker exec lunel-manager install.sh opencode --update
```

## Install coding environments on demand

```bash
docker exec lunel-manager install.sh go
docker exec lunel-manager install.sh go rust node-tools
```

完整支持列表: `go` / `rust` / `node-tools`

## Volumes

| Host path | Container path | Description |
|-----------|---------------|-------------|
| `./data/manager` | `/data` | SQLite 数据库文件（`manager.db`）+ WAL 日志 |

## Environment variables

### Manager

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Listen port | `8899` |
| `MANAGER_ADMIN_PASSWORD` | Admin password (必填) | — |
| `PROXIES` | 预配置的 Proxy URL 列表（逗号分隔） | — |
| `MANAGER_DB_PATH` | SQLite 数据库路径 | `manager.db` |

### Proxy

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Listen port | `3000` |
| `MANAGER_URL` | Manager API URL（必填，需 HTTPS） | — |
| `PUBLIC_URL` | Proxy 公网 URL（必填，需 HTTPS） | — |
| `PROXY_PASSWORD` | Proxy 认证密码（必填） | — |
| `ENFORCE_MANAGER_AUTHORITY` | 是否强制 Manager 校验 | `1` |

## Relay（自建中继）

Lunel 的 Proxy 本身就是中继。部署方式有两种：

### 方式一：独立域名（推荐）

Proxy 使用独立域名，`PUBLIC_URL` 直接设为域名：

```bash
# Proxy 启动参数
PUBLIC_URL=https://relay.example.com
MANAGER_URL=https://manager.example.com
PROXY_PASSWORD=your-proxy-password
```

Caddy 配置：

```caddy
relay.example.com {
  reverse_proxy 127.0.0.1:3000
}
```

### 方式二：二级目录 `/lunel`

如果中继和其他服务共用域名，可部署在 `/lunel` 路径下。**CLI 和 App 均支持带路径的 Proxy URL。**

```bash
# Proxy 启动参数
PUBLIC_URL=https://relay.example.com/lunel    ← 包含路径
MANAGER_URL=https://manager.example.com
PROXY_PASSWORD=your-proxy-password
```

Caddy 配置（`handle_path` 自动剥掉前缀）：

```caddy
relay.example.com {
  handle_path /lunel/* {
    reverse_proxy 127.0.0.1:3000
  }
}
```

**完整链路：**

```
Proxy 注册: PUBLIC_URL=https://relay.example.com/lunel
               ↓
Manager 存储: https://relay.example.com/lunel
               ↓
/v2/proxy 返回: { proxyUrl: "https://relay.example.com/lunel" }
               ↓
CLI WebSocket: wss://relay.example.com/lunel/v2/ws/cli?password=xxx
App WebSocket: wss://relay.example.com/lunel/v2/ws/app?password=xxx
               ↓
Caddy handle_path /lunel/* → 剥掉前缀
               ↓
Proxy 收到标准路径 /v2/ws/cli 和 /v2/ws/app ✓
```

### 自建 Manager + Proxy 的 docker-compose 示例

```yaml
services:
  manager:
    image: ghcr.io/nuln/lunel
    environment:
      PORT: 8899
      MANAGER_ADMIN_PASSWORD: your-admin-password
      PROXIES: "https://relay.example.com"  # 或 https://relay.example.com/lunel
    volumes:
      - ./manager-data:/data

  proxy:
    image: ghcr.io/nuln/lunel
    environment:
      PORT: 3000
      MANAGER_URL: https://manager.example.com
      PUBLIC_URL: https://relay.example.com    # 或 https://relay.example.com/lunel
      PROXY_PASSWORD: your-proxy-password
```

## 架构说明

```
手机 App ──WS──→ Proxy (中继) ←──WS── CLI (本地机器)
                    ↑
                    │ 注册 + 心跳
                    ▼
               Manager (控制面 + SQLite)
```

- Proxy 是 WebSocket 中继网关，不处理业务逻辑
- Manager 是控制面，管理 session 生命周期和权限校验，统一分配 Proxy 地址
- CLI 和 App 的 Proxy 地址均来自 Manager 分配，无需手动配置
- 所有流量端到端加密（libsodium 密封盒），Proxy 看不到明文
