#!/usr/bin/env bash
# =============================================================================
# new-project — scaffold a starter project into the working dir.
#
# Usage:
#   new-project <template> [dir]    scaffold <template> into <dir> (default: cwd)
#   new-project --list             list available templates
#
# Templates are stored under /etc/s6-overlay/templates/<name>/ and get copied
# into the target dir (creating it if needed). Placeholder {{.Project}} in
# filenames and contents is replaced with the project name (dir basename).
# Works with zero network and the image's own toolchains (go / node / wrangler).
# =============================================================================
set -euo pipefail

TPL_ROOT="${NEW_PROJECT_TPL_ROOT:-/etc/s6-overlay/templates}"

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
  echo "Available templates:"
  for t in "$TPL_ROOT"/*/; do
    [ -d "$t" ] || continue
    name="${t%/}"; name="${name##*/}"
    desc=""
    [ -f "$t/README.md.tpl" ] &&     desc="$(sed -n '1s/^# *//p' "$t/README.md.tpl" 2>/dev/null)"
    printf '  %-18s %s\n' "$name" "$desc"
  done
  exit 0
fi

if [ ${#} -lt 1 ] || [ "${1#-}" != "$1" ]; then
  usage
  exit 2
fi

TPL_NAME="$1"
DIR="${2:-.}"
SRC="$TPL_ROOT/$TPL_NAME"

if [ ! -d "$SRC" ]; then
  echo "ERROR: no template '$TPL_NAME'" >&2
  new-project --list >&2
  exit 2
fi

mkdir -p "$DIR"
PROJECT="$(basename "$(cd "$DIR" && pwd)")"

echo "Scaffolding '$TPL_NAME' -> $DIR"

found=0
while IFS= read -r -d '' f; do
  rel="${f#"$SRC"/}"
  found=$((found+1))
  # target path: drop .tpl extension, and handle {{ Project }} in path parts
  tgt="$DIR/$rel"
  tgt="${tgt%.tpl}"
  tgt="${tgt//\{\{ PROJECT \}\}/$PROJECT}"
  [[ "$tgt" == *"{{ PROJECT }}"* ]] && {
    echo "SKIP: unsupported placeholder in path: $rel" >&2; continue; }
  mkdir -p "$(dirname "$tgt")"
  case "$rel" in
    *.tpl) sed "s/{{ PROJECT }}/$PROJECT/g" "$f" > "$tgt"; chmod --reference="$f" "$tgt" 2>/dev/null || true ;;
    *)     cp "$f" "$tgt" ;;
  esac
  echo "  + $tgt"
done < <(find "$SRC" -type f -print0)

[ "$found" -eq 0 ] && { echo "ERROR: template is empty: $SRC" >&2; exit 3; }
echo
echo "Done. Next steps:"
if [ -f "$DIR/go.mod" ] && command -v go >/dev/null 2>&1; then
  echo "  cd $DIR && go mod tidy && go run ."
elif [ -f "$DIR/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
  echo "  cd $DIR && cargo run"
elif [ -f "$DIR/package.json" ] && command -v npm >/dev/null 2>&1; then
  echo "  cd $DIR && npm i && npm run dev"
elif [ -f "$DIR/wrangler.jsonc" ] && command -v wrangler >/dev/null 2>&1; then
  echo "  cd $DIR && wrangler dev -l"
elif [ -f "$DIR/main.py" ] && command -v python3 >/dev/null 2>&1; then
  echo "  cd $DIR && python3 main.py"
fi
echo "  (tip: install a toolchain with: install.sh go|rust|node-tools|bun ...)"