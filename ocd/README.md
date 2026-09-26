# ocd (Open Compute daemon)

> 单二进制、单数据目录的自托管 Cloudflare Workers 兼容计算平台容器镜像。
> 上游项目：[elliothux/open-compute](https://github.com/elliothux/open-compute)

---

## 🌟 特性与功能

- **Cloudflare Workers 深度兼容**：直接支持标准 Module Workers (`export default { fetch }`) 及常用 Wrangler 工作流。
- **全套 Serverless 存储与能力**：内建 KV、D1 (SQLite)、R2 (对象存储)、Durable Objects、Queues、Alarms、Workflows、Vectorize、AI Search 等。
- **单进程极简架构**：基于精简 Rust 核心控制面与经过校验的 `workerd` fork 运行时，无 Redis、无外部数据库 sidecar、无复杂服务网格。
- **多架构支持**：统一支持 `linux/amd64` 与 `linux/arm64`（Apple Silicon / 树莓派 / ARM 服务器）。
- **开箱即用**：首次启动自动完成初始化配置与密钥生成，开箱即提供 `8787` 服务端口与 Cloudflare v4 兼容 API。

---

## 📁 目录结构

```text
ocd/
├── .env.sample          # 环境变量示例文件
├── .gitignore            # 运行时数据忽略规则
├── Dockerfile            # 多架构构建定义（基于 Debian Bookworm 与官方二进制发布包）
├── docker-compose.yml    # Docker Compose 启动配置
├── entrypoint.sh         # 容器启动与自动化环境初始化脚本
└── README.md             # 本说明文档
```

---

## 🚀 快速开始

### 1. 配置环境变量

从示例文件创建 `.env`：

```bash
cp .env.sample .env
```

根据需要编辑 `.env` 中的参数：

```env
# 镜像标签（建议固定版本）
OCD_IMAGE=ghcr.io/nuln/ocd:0.2.1

# 时区与资源限制
TZ=Asia/Shanghai
MEM_LIMIT=1024m
CPU_LIMIT=2

# 监听绑定
OCD_PUBLIC_BIND=0.0.0.0:8787

# 可选：自定义管理与部署 Token（留空则首次启动自动生成）
# OCD_ADMIN_TOKEN=your-admin-token
# OCD_DEPLOYER_TOKEN=your-deployer-token
# OCD_READ_ONLY_TOKEN=your-read-only-token
```

### 2. 启动服务

```bash
docker compose up -d
```

### 3. 查看运行日志与初始 Token

首次启动时，`ocd` 会自动完成初始化并打印配置与 Token 信息：

```bash
docker compose logs -f
```

---

## 🛠️ 使用与部署 Worker

### 本地使用 Wrangler 开发与部署

在您的 Worker 项目目录中：

```bash
# 安装兼容版本的 Wrangler
npm install --save-dev wrangler@4.138.0

# 本地调试
npx wrangler dev

# 部署到 ocd 实例（利用 v4 API）
CLOUDFLARE_API_BASE_URL="http://<宿主机IP>:8787/client/v4" \
CLOUDFLARE_API_TOKEN="<OCD_DEPLOYER_TOKEN>" \
npx wrangler deploy
```

或者在容器内使用 `ocd` CLI 检查实例状态：

```bash
docker compose exec ocd ocd capabilities
```

---

## 📊 打开 Operator Dashboard

在容器内执行生成一次性 Dashboard 登录链接：

```bash
docker compose exec ocd ocd dashboard
```

在浏览器打开输出的 URL 即可访问管理面板。

---

## 🔒 数据持久化与备份

所有运行时数据存储在 Docker 卷 `ocd_data` 中：

- `~/.config/open-compute/config.toml`：计算实例配置文件
- `~/.local/share/open-compute/`：SQLite 数据库、Worker 资产、本地对象与加密主密钥 `keys/master.key`
- `~/.local/share/open-compute/secrets/`：访问控制 Token（`admin.token`、`deployer.token`、`read-only.token`）

> ⚠️ **重要提示**：请妥善备份数据卷中的 `master.key` 与 SQLite 数据库，主密钥丢失将无法解密本地存储凭证。
