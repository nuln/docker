#!/bin/sh
# 一个镜像，按需启动 frpc 或 frps（一次只跑一个）。
#
#   角色：第一个参数（compose 的 command 就是它），默认 frps
#   配置：/etc/frp/<角色>.toml；要换路径或跑子命令就自己带 -c
#
# 配置错误不在这里预检 —— frp 启动时自己会校验，失败即退出（退出码 1），
# 错误信息（字段名、行号）由 frp 直接打进日志。

set -eu

# ---- 选角色：第一个参数就是 compose 的 command ----
case "${1:-}" in
    frpc|frps) ROLE="$1"; shift ;;
    *)         ROLE=frps ;;
esac

# ---- 健康检查 ----
# 这是 Docker 另起的进程（`/entrypoint.sh healthcheck`），走不到下面的启动逻辑。
# exec 启动后 PID 1 就是 frp，确认主进程还是 frpc / frps 之一即可。
if [ "${1:-}" = healthcheck ]; then
    case "$(cat /proc/1/comm 2>/dev/null)" in
        frpc|frps) exit 0 ;;
    esac
    exit 1
fi

# ---- 启动 ----
# 带参数就原样转发；不带参数就用约定路径
[ "$#" -gt 0 ] && exec "/usr/local/bin/$ROLE" "$@"
exec "/usr/local/bin/$ROLE" -c "/etc/frp/$ROLE.toml"
