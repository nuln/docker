#!/command/with-contenv bash
# =============================================================================
# providers.sh — apply opencode provider templates into ~/.pi/agent
#
# Templates live in /etc/s6-overlay/providers/opencode/ (baked into the image):
#   opencode-free.json -> provider "opencode+free"  (8 free models)
#   opencode-go.json   -> provider "opencode+go"    (7 paid models, Go plan)
#
# Simply set OPENCODE_API_KEY and the templates are applied automatically:
#   * opencode+free is always configured.
#   * opencode+go is configured only when a probe finds the key has an active
#     Go subscription (a single 1-token paid request: 200 -> subscribed,
#     401/403 -> not, network failure -> skipped). No extra env vars are needed.
#
# Write behavior (safe incremental, templates are never a destructive source):
#  * First boot / fresh mount (models.json AND auth.json both absent):
#    full rebuild — write both files from the templates.
#  * Later boots (configs already exist): append only, never clobber existing
#    entries. Free is added only if "opencode+free" is missing; when subscribed
#    and a conflicting Go key already exists (e.g. user customized it), the new
#    Go config is written under a new name "opencode+go-2", "opencode+go-3", ...
#    auth.json gets a key entry for every provider this script writes.
#  * Probe says NOT subscribed: Go never written into models/auth; existing Go
#    configs are left untouched, nothing is removed.
#
# Key source: OPENCODE_API_KEY (fallback PI_OPENCODE_API_KEY). Without a key
# nothing is applied (a pre-seeded auth.json in the mount is left untouched).
#
# Manual re-apply (no env vars involved):
#   docker compose exec pi install.sh providers          # same as boot: auto
#   docker compose exec pi install.sh providers --go     # force Go on (skip probe)
#   docker compose exec pi install.sh providers --no     # force Go off
#   docker compose exec pi install.sh providers status   # print state
#
# Runs as an s6 oneshot (pi-provider) on every boot, after wire-plugins and
# before pi-web. Runs as root, then chowns the touched files to user pi.
# =============================================================================
set -euo pipefail

AGENT_DIR="${PI_CODING_AGENT_DIR:-/home/pi/.pi/agent}"
TPL_DIR="${PI_PROVIDER_TPL_DIR:-/etc/s6-overlay/providers/opencode}"
FREE_TPL="$TPL_DIR/opencode-free.json"
GO_TPL="$TPL_DIR/opencode-go.json"
MODELS_JSON="$AGENT_DIR/models.json"
AUTH_JSON="$AGENT_DIR/auth.json"
RUNTIME_UID="${PI_USER_UID:-1000}"
RUNTIME_GID="${PI_USER_GID:-1000}"

KEY="${OPENCODE_API_KEY:-${PI_OPENCODE_API_KEY:-}}"

ZEN_BASE="https://opencode.ai/zen/v1"
# the first paid model in the Go template is used as the Go-subscription probe
# endpoint (1 token). It is read from the template (NOT hardcoded) so it always
# tracks the current Go plan models; falls back if the template is unreadable.
ZEN_PROBE_MODEL="$(jq -r '.providers["opencode+go"].models[0].id' "$GO_TPL" 2>/dev/null || echo deepseek-v4-flash)"

log() { echo "[providers] $*"; }

usage() {
  cat <<'USAGE'
Usage: providers.sh [auto|--go|--no|status]

  auto   probe Go subscription; first boot = full rebuild, later = append (default)
  --go   force treat as Go-subscribed (use right after subscribing, skips probe)
  --no   force treat as not Go-subscribed
  status print current provider/auth state

Requires OPENCODE_API_KEY (or PI_OPENCODE_API_KEY) in the environment.
USAGE
}

# probe_go — 0 subscribed / 1 not subscribed / 2 probe failed (network, non
# 200/401/403, invalid model). Failure is logged, never silently treated as
# "not subscribed": a transient network error must not permanently skip Go.
probe_go() {
  [ -n "$KEY" ] || { echo 2; return 0; }
  local code
  code="$(curl -sS --max-time 8 -o /tmp/pi-go-probe.json -w '%{http_code}' \
    -X POST "$ZEN_BASE/chat/completions" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$ZEN_PROBE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1}" \
    2>/dev/null)" || { echo 2; return 0; }
  case "$code" in
    200)      echo 0 ;;
    401|403)  echo 1 ;;
    *)
      log "WARN: probe for '$ZEN_PROBE_MODEL' returned HTTP $code — network/subscription state unknown"
      echo 2 ;;
  esac
}

# resolve_go — print 1 (subscribed) or 0 (not subscribed). On probe ambiguity
# (2) it retries once before deciding.
resolve_go() {
  local st
  case "$GO_MODE" in
    1)   echo 1; return 0 ;;
    0)   echo 0; return 0 ;;
    auto) : ;;
  esac
  st="$(probe_go)"
  if [ "$st" = "2" ]; then
    log "retrying Go probe once (transient errors are not treated as unsubscribed)"
    st="$(probe_go)"
  fi
  case "$st" in
    0) echo 1 ;;
    *) echo 0 ;;
  esac
}

# sync_state <go_on> — write/merge templates into models.json + auth.json.
# Prints a human log line per action taken.
sync_state() {
  local go_on="$1"
  [ -n "$KEY" ] || { log "no OPENCODE_API_KEY set — not applying provider templates"; return 0; }
  [ -f "$FREE_TPL" ] || { log "missing template $FREE_TPL" >&2; return 1; }
  [ "$go_on" = "1" ] && [ ! -f "$GO_TPL" ] && { log "missing template $GO_TPL" >&2; return 1; }
  mkdir -p "$AGENT_DIR"

  python3 - "$MODELS_JSON" "$AUTH_JSON" "$FREE_TPL" "$GO_TPL" "$KEY" "$go_on" <<'PY'
import json, sys, os
models_f, auth_f, free_f, go_f, key, go_on = sys.argv[1:]
go_on = (go_on == "1")

def load_valid(path):
    """Return parsed dict, or None if missing/unparseable/wrong shape."""
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        return None
    return data if isinstance(data, dict) else None

free = load_valid(free_f)
go = load_valid(go_f)
prov_free = free.get("providers", {}) if free and isinstance(free.get("providers"), dict) else None
prov_go = go.get("providers", {}) if go and isinstance(go.get("providers"), dict) else None
if prov_free is None:
    raise SystemExit(f"providers: invalid template {free_f}")
if go_on and prov_go is None:
    raise SystemExit(f"providers: invalid template {go_f}")

models_missing = not os.path.exists(models_f)
auth_missing = not os.path.exists(auth_f)
models = load_valid(models_f) if not models_missing else None
auth = load_valid(auth_f) if not auth_missing else None
full_rebuild = models_missing and auth_missing  # first boot / fresh mount
touched = []      # actions in this run
models_writable = True
auth_writable = True

if full_rebuild:
    providers = dict(prov_free)
    if go_on:
        providers.update(prov_go)
    models = {"providers": providers}
    auth = {"opencode+free": {"type": "api_key", "key": key}}
    if go_on:
        auth["opencode+go"] = {"type": "api_key", "key": key}
    print("  - full rebuild (first boot / fresh mount)")
else:
    # ---- models.json ----
    if models is None:
        if models_missing:
            providers = dict(prov_free)
            if go_on:
                providers.update(prov_go)
            models = {"providers": providers}
            touched.append("models.json created from templates")
        else:
            # exists but corrupt -> never touch it
            print("WARN: models.json exists but is unparseable/corrupt — left untouched")
            providers = {}
            models_writable = False
    elif not isinstance(models, dict) or not isinstance(models.get("providers"), dict):
        print("WARN: models.json has no usable 'providers' — left untouched")
        providers = {}
        models_writable = False
    else:
        providers = dict(models["providers"])
        if "opencode+free" not in providers:
            providers["opencode+free"] = dict(prov_free["opencode+free"])
            touched.append("added provider 'opencode+free'")
        if go_on:
            name = "opencode+go"
            i = 2
            while name in providers:
                name = f"opencode+go-{i}"; i += 1
            providers[name] = dict(prov_go["opencode+go"])
            touched.append(f"added provider '{name}' (subscribed)")
        models["providers"] = providers

    # ---- auth.json ----
    if auth_missing:
        auth = {"opencode+free": {"type": "api_key", "key": key}}
        if go_on:
            auth["opencode+go"] = {"type": "api_key", "key": key}
        touched.append("auth.json created")
    elif auth is None or not isinstance(auth, dict):
        print("WARN: auth.json exists but is unparseable/corrupt — left untouched")
        auth_writable = False
    else:
        if "opencode+free" in providers and "opencode+free" not in auth:
            auth["opencode+free"] = {"type": "api_key", "key": key}
        # every go-named provider present in models gets a key (incl. renames)
        for name in providers:
            if name.startswith("opencode+go") and name not in auth:
                auth[name] = {"type": "api_key", "key": key}

if models_writable:
    json.dump(models, open(models_f, "w"), indent=2, ensure_ascii=False)
if auth_writable:
    json.dump(auth, open(auth_f, "w"), indent=2, ensure_ascii=False)

n_free = len(prov_free.get("opencode+free", {}).get("models", []))
print(f"free models: {n_free}")
go_names = sorted(n for n in (providers if models_writable else {}) if n.startswith("opencode+go"))
print(f"go providers: {', '.join(go_names) if go_names else 'not configured'}")
for t in touched:
    print(f"  - {t}")
PY
}

status() {
  echo "== provider templates =="
  echo "  free: $FREE_TPL $( [ -f "$FREE_TPL" ] && echo present || echo MISSING)"
  echo "  go:   $GO_TPL $( [ -f "$GO_TPL" ] && echo present || echo MISSING)"
  echo "== agent state =="
  echo "  models.json : $MODELS_JSON"
  if [ -f "$MODELS_JSON" ]; then
    jq -r '.providers | to_entries[] | "    \(.key): \(.value.models | length) models"' "$MODELS_JSON" 2>/dev/null \
      || echo "    (unparseable)"
  else
    echo "    (absent)"
  fi
  echo "  auth.json   : $AUTH_JSON"
  if [ -f "$AUTH_JSON" ]; then
    jq -r 'to_entries[] | "    \(.key): \(.value.type // "?")"' "$AUTH_JSON" 2>/dev/null || echo "    (unparseable)"
  else
    echo "    (absent)"
  fi
}

case "${1:-auto}" in
  --go|-g)        GO_MODE=1 ;;
  --no|-n)        GO_MODE=0 ;;
  auto)           GO_MODE=auto ;;
  status)         status; exit 0 ;;
  -h|--help|help) usage; exit 0 ;;
  *) echo "unknown option: $1" >&2; usage; exit 1 ;;
esac

go_on="$(resolve_go)"
if [ "$GO_MODE" = "1" ]; then
  log "Go plan state: forced ON"
elif [ "$GO_MODE" = "0" ]; then
  log "Go plan state: forced OFF"
elif [ "$go_on" = "1" ]; then
  log "Go plan state: subscribed (probe OK)"
else
  log "Go plan state: not subscribed / probe skipped"
fi

sync_state "$go_on"

chown "$RUNTIME_UID:$RUNTIME_GID" "$MODELS_JSON" "$AUTH_JSON" 2>/dev/null || true
exit 0