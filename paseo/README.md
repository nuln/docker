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
