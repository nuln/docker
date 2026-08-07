#!/command/with-contenv bash
# =============================================================================
# wire-plugins — s6 oneshot service: DERIVE settings.json from the baked store
#
# Runs once on first start, as root (PID 1 is s6's /init). The preinstalled
# plugin store is baked into the image at /home/pi/.pi-plugins/npm (NOT the
# runtime config dir ~/.pi, which is a bind mount ./data/pi that shadows image
# content).
#
# pi reads exactly one global settings file ($PI_CODING_AGENT_DIR/settings.json,
# parsed with JSON.parse). If the mounted agent dir has no settings.json yet, we
# DERIVE one by scanning the baked store — we do NOT copy a bake-time file. Three
# rules must hold for the generated file (verified against pi's own
# settings-manager / package-manager source):
#   1. valid JSON          — JSON.parse failure makes pi silently treat settings as
#                            empty and load nothing; we emit via jq (json -j).
#   2. absolute paths      — pi resolves local relative paths against ~/.pi/agent,
#                            not /home/pi/.pi-plugins, so entries must be absolute.
#   3. only real plugins — a dir is a plugin when its package.json declares a
#                          `pi` manifest (pi's own settings-manager rule; this is
#                          exactly what `pi install npm:<pkg>` records). Convention
#                          dirs / index entry points are deliberately NOT enough:
#                          plain npm deps (e.g. @protobufjs/base64, @noble/ed25519)
#                          ship index.js and would be mis-flagged as plugins. npm
#                          scoped pkgs, node_modules/@scope/name, are handled too.
#
# If a settings.json already exists we do nothing — user config and user-installed
# plugins in the mount are never touched. Runs as root, then chowns the file to
# the container user (pi, uid 1000).
#
# with-contenv injects the container environment (PI_*) into this script.
# =============================================================================
set -euo pipefail

AGENT_DIR="${PI_CODING_AGENT_DIR:-/home/pi/.pi/agent}"
STORE=/home/pi/.pi-plugins/npm/node_modules
RUNTIME_UID="${PI_USER_UID:-1000}"
RUNTIME_GID="${PI_USER_GID:-1000}"
OUT="$AGENT_DIR/settings.json"

# Already configured (e.g. user pre-seeded it, or a previous boot) — never touch it.
if [ -e "$OUT" ]; then
  echo "[s6:wire-plugins] $OUT exists — leaving user config untouched"
  exit 0
fi

if [ ! -d "$STORE" ]; then
  echo "[s6:wire-plugins] baked store missing: $STORE — nothing to wire"
  exit 0
fi

mkdir -p "$AGENT_DIR"

# Seed a baked permission policy for pi-permission-system, ONLY when the user
# opts in via PI_PERMISSION_SYSTEM_POLICY (allow|ask|default|deny|hardened).
# Empty -> nothing is seeded; the plugin keeps its built-in behaviour. An
# existing config in the mount ALWAYS wins.
if [ -n "${PI_PERMISSION_SYSTEM_POLICY:-}" ]; then
  PERM_EXT="$AGENT_DIR/extensions/pi-permission-system"
  PERM_CFG="$PERM_EXT/config.json"
  PERM_POLICY="${PI_PERMISSION_SYSTEM_POLICY}"
  PERM_SEED="/etc/s6-overlay/plugins/pi-permission-system/policies/${PERM_POLICY}.json"
  if [ -e "$PERM_CFG" ]; then
    echo "[s6:wire-plugins] $PERM_CFG exists — existing policy wins, env ignored"
  elif [ -e "$PERM_SEED" ]; then
    mkdir -p "$PERM_EXT"
    cp "$PERM_SEED" "$PERM_CFG"
    chown "$RUNTIME_UID:$RUNTIME_GID" "$PERM_EXT" "$PERM_CFG" 2>/dev/null || true
    echo "[s6:wire-plugins] seeded permission policy '$PERM_POLICY' -> $PERM_CFG"
  else
    echo "[s6:wire-plugins] no baked policy for PI_PERMISSION_SYSTEM_POLICY='$PERM_POLICY' (try allow|ask|default|deny|hardened)"
  fi
fi

# Bake in curated skills from the image (/etc/s6-overlay/plugins/skills) into
# pi's global skills dir (~/.agents/skills) on first boot.
#   PI_SKILLS=true            -> copy ALL baked skills
#   PI_SKILLS=a,b,c           -> copy only those (whitelist), unknown names are
#                                skipped with a notice
#   PI_SKILLS=false|empty     -> skills stay in the image, NOT loaded (default)
if [ "${PI_SKILLS:-false}" != "false" ] && [ -n "${PI_SKILLS:-}" ]; then
  SKILL_SRC="/etc/s6-overlay/plugins/skills"
  SKILL_DST="/home/pi/.agents/skills"
  if [ -d "$SKILL_SRC" ]; then
    mkdir -p "$SKILL_DST"
    if [ "${PI_SKILLS}" = "true" ]; then
      cp -a "$SKILL_SRC"/. "$SKILL_DST"/
      echo "[s6:wire-plugins] copied ALL baked skills -> $SKILL_DST ($(find "$SKILL_DST" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ') skills)"
    else
      LOADED=0; MISSING=0
      while read -r name; do
        [ -n "$name" ] || continue
        if [ -d "$SKILL_SRC/$name" ]; then
          cp -a "$SKILL_SRC/$name" "$SKILL_DST/"
          LOADED=$((LOADED+1))
        else
          printf 'WARN: [s6:wire-plugins] no baked skill named "%s" (available: %s)\n' "$name" "$(ls "$SKILL_SRC")" >&2
          MISSING=$((MISSING+1))
        fi
      done < <(printf '%s' "${PI_SKILLS}" | tr ',' '\n' | sed 's/[[:space:]]//g' | grep -v '^$')
      echo "[s6:wire-plugins] whitelist loaded -> $SKILL_DST (loaded=$LOADED skipped_unknown=$MISSING)"
    fi
    chown -R "$RUNTIME_UID:$RUNTIME_GID" "$SKILL_DST" 2>/dev/null || true
  else
    echo "[s6:wire-plugins] PI_SKILLS set but no baked skills at $SKILL_SRC"
  fi
fi

# Collect every package dir under the store (top-level, including scoped @scope/name
# subdirs). A dir is a plugin iff its package.json declares a `pi` manifest — the
# same rule pi's settings-manager uses, so this matches what `pi install npm:...`
# would have recorded. Emit paths one per line; jq builds the JSON.
: > "$OUT"
for pkg in "$STORE"/*/ "$STORE"/@*/*/; do
  [ -e "$pkg" ] || continue
  pkg="${pkg%/}"
  if jq -e '.pi' "$pkg/package.json" >/dev/null 2>&1; then
    printf '%s\n' "$pkg"
  fi
done | sort -u | jq -R -s 'split("\n") | map(select(length > 0)) | {packages: .}' > "$OUT"

chown "$RUNTIME_UID:$RUNTIME_GID" "$OUT" 2>/dev/null || true

COUNT="$(jq '.packages | length' "$OUT")"
echo "[s6:wire-plugins] generated $COUNT baked plugins (absolute paths, no copy) -> $OUT"