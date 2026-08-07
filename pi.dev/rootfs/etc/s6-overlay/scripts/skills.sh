#!/usr/bin/env bash
# =============================================================================
# skills — inspect which curated skills are loaded into ~/.agents/skills.
#
# Skills sit in the image at /etc/s6-overlay/plugins/skills but are only copied
# into pi's global skills dir (~/.agents/skills) when PI_SKILLS is set (true or
# a whitelist). Use this command inside the container to self-check the result.
#
# Usage:
#   skills            show loaded skills (dir name + SKILL.md description)
#   skills -a         show ALL baked skills that exist in the image
#   skills <name>     confirm a single skill is loaded (exit 0 loaded / 1 if not)
# =============================================================================
set -uo pipefail

BAKED="${PI_SKILLS_SRC:-/etc/s6-overlay/plugins/skills}"
LOADED="${PI_SKILLS_DST:-/home/pi/.agents/skills}"

desc() {
  local d="$1"
  if [ -f "$d/SKILL.md" ]; then
    awk '/^description:/{ sub(/^description:[[:space:]]*/,""); print; exit }' "$d/SKILL.md"
  fi
}

list_dir() {
  local dir="$1" label="$2"
  local missing=0 n
  if [ ! -d "$dir" ]; then
    echo "$label: none"
    return 0
  fi
  echo "$label:"
  for d in "$dir"/*/; do
    [ -d "$d" ] || continue
    printf '  %-18s %s\n' "$(basename "$d")" "$(desc "$d")"
  done
}

case "${1:-list}" in
  --list|list|-l)
    list_dir "$LOADED" "loaded (~/.agents/skills)"
    ;;
  available|avail|-a)
    list_dir "$BAKED" "available (image /etc/s6-overlay/plugins/skills)"
    ;;
  --help|-h|help)
    sed -n '1,13p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    name="${1#*}"
    if [ -d "$LOADED/${name##*/}" ]; then
      echo "yes: '$name' is loaded into ~/.agents/skills"
      exit 0
    fi
    if [ -d "$BAKED/${name##*/}" ]; then
      echo "no: '$name' is available but NOT loaded (add it to PI_SKILLS)" >&2
      exit 1
    fi
    echo "no: no skill named '$name'" >&2
    exit 1
    ;;
esac