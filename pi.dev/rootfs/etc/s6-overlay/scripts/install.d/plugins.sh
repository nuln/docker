#!/usr/bin/env bash
# =============================================================================
# install.d/plugins.sh — pi plugin installer (loaded by install.sh)
#   desc: pi plugins (batch install by group: all|--core|--perms|--im|--web|--remote|--memory)
#   tool: plugins
#   fn:   install_plugins
#   usage: install.sh plugins [all|--core|--perms|--im|--web|--remote|--memory]
#
# Only one plugin per category per group, to avoid tool-name collisions. To install more or fewer,
# add/remove entries in the arrays below — no change to install.sh needed.
#
# Every entry is pinned as <name>@<version> (never bare "latest"). Bump versions
# deliberately; install.sh / versions.env keep the same pins so installs are reproducible.
# =============================================================================

# Core group: "the" entry plugin set — MCP ecosystem + subagents + web search + LSP + permission gate
CORE_PLUGINS=(
  "pi-mcp-adapter@2.21.1"                   # MCP ecosystem entry point
  "pi-subagents@0.44.0"                     # subagent dispatch / parallel
  "pi-web-access@0.19.0"                    # web search/scrape/PDF/video
  "pi-lens@3.8.74"                          # real-time code feedback (LSP)
  "@gotgenes/pi-permission-system@24.0.0"   # permission gate (allow/ask/deny)
  "@narumitw/pi-statusline@0.49.5"          # statusline
)

# Permissions/security group: gate + session audit + pre-install source review
PERMS_PLUGINS=(
  "@gotgenes/pi-permission-system@24.0.0"   # required: intercept before execution (allow/ask/deny)
  "@vigolium/piolium@0.0.13"                # recommended: multi-stage security audit
  "@panzenbaby/pi-secure-extension@0.1.3"   # optional: LLM source review before install, guards against malicious packages
)

# IM chat group: Telegram + Feishu/Lark + WeChat (one plugin per channel, no conflicts)
IM_PLUGINS=(
  "@llblab/pi-telegram@0.27.2"      # Telegram: official bot integration (long polling/webhook)
  "pi-feishu-lark@0.2.4"            # Feishu/Lark: scan to create bot, per-group/topic sessions
  "pi-wechat-assistant@0.3.0"       # WeChat: iLink scan-to-connect, WeChat as a mobile remote for one pi session
)

# Web UI group: lightweight OpenWebUI style, pi --web one-command start (port 3141)
WEB_PLUGINS=(
  "pi-web-chat@0.1.16"
)

# Remote control group: Flutter iOS/Android native App + self-hosted relay
REMOTE_PLUGINS=(
  "remote-pi@0.5.5"
)

# Memory group: SQLite FTS5 search + secret scanning (user-chosen)
MEMORY_PLUGINS=(
  "pi-hermes-memory@0.9.4"
)

install_plugins() {
  local mode="${1:-all}"
  local pick=()

  # ---- Select group(s) by argument ----
  case "$mode" in
    --core)   pick=( "${CORE_PLUGINS[@]}" ) ;;
    --perms)  pick=( "${PERMS_PLUGINS[@]}" ) ;;
    --im)     pick=( "${IM_PLUGINS[@]}" ) ;;
    --web)    pick=( "${WEB_PLUGINS[@]}" ) ;;
    --remote) pick=( "${REMOTE_PLUGINS[@]}" ) ;;
    --memory) pick=( "${MEMORY_PLUGINS[@]}" ) ;;
    all)
      pick=( "${CORE_PLUGINS[@]}" "${PERMS_PLUGINS[@]}" "${IM_PLUGINS[@]}"
             "${WEB_PLUGINS[@]}" "${REMOTE_PLUGINS[@]}" "${MEMORY_PLUGINS[@]}" ) ;;
    *)
      echo "usage: install.sh plugins [all|--core|--perms|--im|--web|--remote|--memory]" >&2
      exit 1
      ;;
  esac

  # ---- De-duplicate (permission-system appears in both PERMS and CORE, avoid installing twice) ----
  mapfile -t pick < <(printf '%s\n' "${pick[@]}" | awk '!seen[$0]++')

  echo "[install] About to install ${#pick[@]} pi plugins:"
  printf '  - %s\n' "${pick[@]}"

  # ---- Confirm (only prompts when stdin is a TTY; skipped automatically in non-interactive
  #      environments such as `docker compose exec pi install.sh plugins ...` without `-it`.
  #      Add `-it` interactively, or the install proceeds immediately.) ----
  if [[ -t 0 ]]; then
    read -r -p "Continue? [Y/n] " ans
    [[ "${ans,,}" == "n" ]] && { echo "Cancelled."; return 0; }
  else
    echo "[install] Non-interactive mode (no TTY): continuing without confirmation."
  fi

  # ---- Install one by one (pi install accepts one source at a time) ----
  command -v pi >/dev/null 2>&1 || { echo "[binstall] error: pi command not found (now in container)" >&2; exit 1; }
  local fail=0 pkg
  for pkg in "${pick[@]}"; do
    echo "  -> pi install npm:$pkg"
    if ! pi install "npm:$pkg" 2>&1; then
      echo "  !! install failed: npm:$pkg (you can retry it manually later)"
      fail=$((fail + 1))
    fi
  done

  # ---- Result ----
  if [[ $fail -gt 0 ]]; then
    echo "[install] $fail plugin(s) failed. Check installed ones with pi list."
  else
    echo "[install] All plugins installed. Check with pi list."
  fi
  echo "[install] IM channels still need their own bot tokens (see README): Telegram/Feishu/WeChat."
}