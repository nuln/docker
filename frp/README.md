# frp

**一个镜像，两个二进制**：`frpc` 和 `frps` 都装在里面，启动哪个由 `command` 决定。**一次只跑一个。**

上游本来就用同一个 release 包发布两个二进制（同一次编译、同一版本），而且都是静态二进制，所以合成一个镜像没有额外成本：省一次构建、省一个 tag、两端版本天然一致。

镜像只做两件事：**按需启动**、**检查主进程存活**。配置内容全部由你维护，本仓库不附带任何配置模板或生成脚本。

## 文件

```
frp/
├── Dockerfile                    两个二进制 + 校验和 + UPX 压缩 + HEALTHCHECK
├── entrypoint.sh                 唯一的脚本：选角色 / 启动 / 健康检查
├── .gitignore
└── README.md
```

## 快速开始

```bash
# 服务端：起 frps，挂载自己的配置目录
docker run -d --name frps \
  -p 7000:7000 \
  -p 6000:6000 \
  -v /path/to/frp/conf:/etc/frp:ro \
  -e TZ=Asia/Shanghai \
  --restart unless-stopped \
  ghcr.io/nuln/frp:0.71.0 frps
```

```bash
# 客户端：起 frpc
docker run -d --name frpc \
  -v /path/to/frp/conf:/etc/frp:ro \
  -e TZ=Asia/Shanghai \
  --restart unless-stopped \
  ghcr.io/nuln/frp:0.71.0 frpc
```

配置放在宿主机的 `/path/to/frp/conf/` 里，容器读 `/etc/frp/frps.toml` 或 `/etc/frp/frpc.toml`。可参考 [frp 官方示例](https://github.com/fatedier/frp/tree/dev/conf)。

一个最小可用的服务端配置：

```toml
bindPort = 7000
[auth]
method = "token"
token = "你的随机 token"
```

客户端配置：

```toml
serverAddr = "你的 frps 地址"
serverPort = 7000
[auth]
method = "token"
token = "和服务端一致的 token"

[[proxies]]
name = "ssh"
type = "tcp"
localIP = "host.docker.internal"
localPort = 22
remotePort = 6000
```

> ⚠️ **`remotePort` 每一个都要用 `-p` 发布到宿主机。**
> 漏掉的话 frps 会在容器内正常监听、日志也一切正常（`start proxy success`），
> 但从外面访问不通——因为端口没发布。这是部署 frp 最常见的第一个坑。
>
> 容器里 `127.0.0.1` 指向**容器自己**，不是宿主机。用 `host.docker.internal`（需加
> `--add-host host.docker.internal:host-gateway`），或同一 docker 网络里的容器名。

## 版本与镜像

版本 **pin 在 `Dockerfile` 的 `ARG FRP_VERSION`**，手动 bump。CI 从这个 ARG 读取版本号作为镜像 tag。

```bash
# 本地构建
docker build -t frp:local frp

# 升级 frp：改 FRP_VERSION，push，CI 自动构建
```

```
ghcr.io/nuln/frp:0.71.0    # 版本 tag
ghcr.io/nuln/frp:latest    # 跟随最新一次构建
```

**架构**：`linux/amd64` + `linux/arm64`。

**构建阶段做的事**（工具链不进最终镜像）：下载官方 tarball → 用官方 `frp_sha256_checksums.txt` 校验 → 用 UPX 压缩两个二进制。压缩后仍跑一次 `-v` 自检，压坏了就换回原版。最终镜像 **37MB**（未压缩 70MB），里面只有 alpine + `ca-certificates` + `tzdata` + 两个二进制。

镜像里没有 `curl`（构建工具链不带进最终镜像），容器内排查用 busybox 的 `wget` / `nc`。

## 角色是怎么选的

**就是 `command`**，没有别的开关：

| 写法 | 启动 |
|---|---|
| `docker run … IMAGE` | frps（默认） |
| `docker run … IMAGE frpc` | frpc |
| `docker run … IMAGE frps -c /other/path.toml` | frps + 指定配置 |

配置路径固定 `/etc/frp/<角色>.toml`（即挂载点的位置），要换路径就自己带 `-c`。带任何参数时参数原样转发给 frp。

## 健康检查

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
  CMD ["/entrypoint.sh", "healthcheck"]
```

检查的是**主进程**：entrypoint 用 `exec` 启动 frp，所以 PID 1 就是 frp 本身，确认它还是 `frpc` / `frps` 之一即可。一次只跑一个角色，这里也只查这一个主进程，不扫进程表。

```bash
docker exec frps /entrypoint.sh healthcheck
docker inspect -f '{{.State.Health.Status}}' frps
```

**它查不出什么**：只查进程存活，查不出"进程在跑但连不上服务端"。后者 frp 自己会处理 —— 首次登录失败时默认 `loginFailExit=true`，frpc 直接退出，容器跟着重启。实测确认：**已连上的 frpc 不会因为 frps 崩溃而退出**，它会自己重连。

## 常用运维命令

```bash
# 校验配置，不启动
docker run --rm -v /path/to/frp/conf:/etc/frp:ro ghcr.io/nuln/frp:0.71.0 frps verify -c /etc/frp/frps.toml
docker run --rm -v /path/to/frp/conf:/etc/frp:ro ghcr.io/nuln/frp:0.71.0 frpc verify -c /etc/frp/frpc.toml

docker logs -f frps
docker restart frps                                  # token / 端口改动必须重启
docker exec frps /entrypoint.sh healthcheck
docker exec frps sh -c 'nc -zv 127.0.0.1 7000'      # 临时排查
```

**配置错误不需要预检** —— frp 启动时自己会校验，失败即退出（退出码 1），错误信息（字段名、行号）由 frp 直接打进日志：

```
$ docker run --rm -v ./conf:/etc/frp:ro IMAGE frps -c /etc/frp/frps.toml   # bindPort 写成字符串
field "bindPort": cannot unmarshal string into int
$ echo $?
1
```

frp 的子命令在两个角色上**不对称**（0.71.0 实测）：

| 子命令 | frps | frpc |
|---|---|---|
| `verify` | ✅ | ✅ |
| `reload` / `status` / `stop` | ❌ | ✅（需在配置里开 `[webServer]`） |
| `tcp` / `http` / `stcp` 等单代理快捷方式 | ❌ | ✅（自带参数，不用配置文件） |

对 `frps` 用 `reload`/`status`，frp 自己会报 `unknown command`。服务端状态建议开 dashboard 后查 `/api/serverinfo`。

## 常用配置项

需要时自己加，`verify` 会在启动前校验：

**frps**

```toml
# 限制客户端能申请的端口范围。不限制的话任何通过认证的客户端都能占任意端口
allowPorts = [{ start = 20000, end = 20100 }]

# Dashboard（默认关闭）。不设 user/password 就是无认证，等于把面板暴露到公网
[webServer]
addr = "0.0.0.0"
port = 7500
user = "admin"
password = "{{ .Envs.FRP_DASHBOARD_PASSWORD }}"   # 走环境变量，别写死

# 按域名转发（需要域名，通常会和 Caddy 抢 80/443）
vhostHTTPPort = 80
vhostHTTPSPort = 443
subDomainHost = "frp.example.com"
```

**frpc**

```toml
# 按域名转发
[[proxies]]
name = "web"
type = "http"
localIP = "host.docker.internal"
localPort = 3000
customDomains = ["app.example.com"]

# stcp：只有带同样 secretKey 的客户端能连，公网上不暴露端口
[[proxies]]
name = "db"
type = "stcp"
secretKey = "another-secret"
localIP = "host.docker.internal"
localPort = 3306

[[visitors]]
name = "db-visitor"
type = "stcp"
serverName = "db"
secretKey = "another-secret"
bindAddr = "127.0.0.1"
bindPort = 13306

# 连不上时原地重试而不是退出（默认 loginFailExit = true 会退出）
# loginFailExit = false
```

## 已知行为

- **`docker stop` 后退出码是 2 而不是 0/143**：Go 运行时在 PID 1 位置收到 `SIGTERM` 时无法走 reset+re-raise，会调 `exit(2)`。上游行为，不影响容器生命周期。
- **改了配置必须重启**：frps 没有 `reload`；frpc 的 `reload` 也只对部分字段生效，`serverAddr`/`token` 这类必须重启。
- **首次登录失败会退出**：frp 默认 `loginFailExit=true`，frpc 连不上就退出，容器跟着重启 —— 这是刻意的（配置错了要立刻暴露）。想让客户端原地重试就设 `loginFailExit = false`。

## CI

`.github/workflows/frp.yml`，三道检查：

1. **两个二进制版本核对** —— 镜像里 `frpc -v` / `frps -v` 都要等于 tag 版本，防止 bump 了 ARG 却推了旧镜像
2. **端到端冒烟** —— 起 frps + frpc + 源服务三个容器，确认登录成功、代理注册成功、健康检查通过；再从宿主机发一次请求确认**数据真的穿过隧道**（控制通道通了不代表数据能过去，这一步同时验证 UPX 压缩没破坏转发）；最后杀掉 frps，确认 frpc 不会跟着死
3. **多架构** —— `linux/amd64` + `linux/arm64` 同时推送

## 参考

- [frp 官方文档](https://github.com/fatedier/frp)
- [frp 配置文档](https://gofrp.org/docs/features/common/network/network-conf/)
