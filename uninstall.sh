#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
PATCHED_FILES=(
  "hermes_cli/commands.py"
  "hermes_cli/cli_commands_mixin.py"
  "gateway/slash_commands_model.py"
  "gateway/run_busy.py"
  "tui_gateway/methods_slash.py"
)
MODULE_FILE="hermes_cli/soul_switcher.py"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

is_hermes_dir() {
  [ -f "$1/run_agent.py" ] && [ -f "$1/hermes_cli/commands.py" ]
}

locate_hermes() {
  local candidate wrapper entry
  if [ "$#" -gt 0 ] && [ -n "$1" ]; then
    is_hermes_dir "$1" || die "not a Hermes source installation: $1"
    (cd "$1" && pwd -P)
    return
  fi
  for candidate in \
    "${HERMES_INSTALL_DIR:-}" \
    "$HERMES_HOME_DIR/hermes-agent" \
    "/usr/local/lib/hermes-agent" \
    "/opt/hermes-agent"; do
    if [ -n "$candidate" ] && is_hermes_dir "$candidate"; then
      (cd "$candidate" && pwd -P)
      return
    fi
  done
  wrapper="$(command -v hermes 2>/dev/null || true)"
  if [ -n "$wrapper" ] && [ -f "$wrapper" ]; then
    entry="$(sed -n 's|.*"\([^"]*/hermes\)" "\$@".*|\1|p' "$wrapper" | head -n 1)"
    candidate="${entry%/hermes}"
    if [ -n "$entry" ] && is_hermes_dir "$candidate"; then
      (cd "$candidate" && pwd -P)
      return
    fi
  fi
  while IFS= read -r candidate; do
    candidate="${candidate%/run_agent.py}"
    if is_hermes_dir "$candidate"; then
      (cd "$candidate" && pwd -P)
      return
    fi
  done < <(find "$HERMES_HOME_DIR" -maxdepth 3 -type f -name run_agent.py 2>/dev/null || true)
  die "could not locate Hermes. Re-run as: HERMES_INSTALL_DIR=/path/to/hermes-agent ./uninstall.sh"
}

HERMES_DIR="$(locate_hermes "${1:-}")"
BACKUP_DIR="$HERMES_DIR/.soul-switcher-backup"
[ -f "$BACKUP_DIR/installed" ] || { say "Hermes Soul Switcher is not installed here. Nothing changed."; exit 0; }

[ "$(basename "$BACKUP_DIR")" = ".soul-switcher-backup" ] || die "refusing unsafe backup path"
ORIGINAL_HOME="$(sed -n '1p' "$BACKUP_DIR/hermes-home" 2>/dev/null || true)"
[ -n "$ORIGINAL_HOME" ] || die "backup is missing its Hermes home path"
[ "$ORIGINAL_HOME" != "/" ] || die "refusing unsafe Hermes home path"

for rel in "${PATCHED_FILES[@]}"; do
  [ -f "$BACKUP_DIR/original/$rel" ] || die "backup is incomplete: missing $rel"
  cp -p "$BACKUP_DIR/original/$rel" "$HERMES_DIR/$rel"
done

if [ -f "$BACKUP_DIR/module-was-absent" ]; then
  rm -f "$HERMES_DIR/$MODULE_FILE"
  if [ -d "$HERMES_DIR/hermes_cli/__pycache__" ]; then
    find "$HERMES_DIR/hermes_cli/__pycache__" -type f -name 'soul_switcher.*.pyc' -delete
  fi
elif [ -f "$BACKUP_DIR/original/$MODULE_FILE" ]; then
  cp -p "$BACKUP_DIR/original/$MODULE_FILE" "$HERMES_DIR/$MODULE_FILE"
else
  die "backup does not describe the original module state"
fi

if [ -f "$BACKUP_DIR/soul-was-absent" ]; then
  rm -f "$ORIGINAL_HOME/SOUL.md"
elif [ -f "$BACKUP_DIR/user/SOUL.md" ]; then
  mkdir -p "$ORIGINAL_HOME"
  cp -p "$BACKUP_DIR/user/SOUL.md" "$ORIGINAL_HOME/SOUL.md"
else
  die "backup does not describe the original SOUL.md state"
fi

rm -rf -- "$BACKUP_DIR"
say "Uninstalled Hermes Soul Switcher and restored the original Hermes files."
say "Saved souls were kept in $ORIGINAL_HOME/souls"
say "Restart any running Hermes process once."
