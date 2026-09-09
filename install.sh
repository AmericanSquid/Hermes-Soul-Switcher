#!/usr/bin/env bash
set -euo pipefail

MOD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HERMES_HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
PATCHED_FILES=(
  "hermes_cli/commands.py"
  "hermes_cli/cli_commands_mixin.py"
  "gateway/slash_commands_model.py"
  "gateway/run_busy.py"
  "tui_gateway/methods_slash.py"
)
MODULE_FILE="hermes_cli/soul_switcher.py"
INSTALL_STARTED=0

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

is_hermes_dir() {
  local dir="$1"
  [ -f "$dir/run_agent.py" ] &&
    [ -f "$dir/hermes_cli/commands.py" ] &&
    [ -f "$dir/gateway/run_busy.py" ]
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

  die "could not locate Hermes. Re-run as: HERMES_INSTALL_DIR=/path/to/hermes-agent ./install.sh"
}

restore_originals() {
  local rel
  for rel in "${PATCHED_FILES[@]}"; do
    [ -f "$BACKUP_DIR/original/$rel" ] && cp -p "$BACKUP_DIR/original/$rel" "$HERMES_DIR/$rel"
  done
  if [ -f "$BACKUP_DIR/module-was-absent" ]; then
    rm -f "$HERMES_DIR/$MODULE_FILE"
  elif [ -f "$BACKUP_DIR/original/$MODULE_FILE" ]; then
    cp -p "$BACKUP_DIR/original/$MODULE_FILE" "$HERMES_DIR/$MODULE_FILE"
  fi
  if [ -f "$BACKUP_DIR/soul-was-absent" ]; then
    rm -f "$HERMES_HOME_DIR/SOUL.md"
  elif [ -f "$BACKUP_DIR/user/SOUL.md" ]; then
    cp -p "$BACKUP_DIR/user/SOUL.md" "$HERMES_HOME_DIR/SOUL.md"
  fi
}

cleanup_failed_install() {
  local status=$?
  trap - ERR
  set +e
  if [ "$INSTALL_STARTED" -eq 1 ]; then
    restore_originals
    if [ "$(basename "$BACKUP_DIR")" = ".soul-switcher-backup" ]; then
      rm -rf -- "$BACKUP_DIR"
    fi
  fi
  exit "$status"
}

rollback_and_die() {
  local message="$1"
  trap - ERR
  set +e
  restore_originals
  [ "$(basename "$BACKUP_DIR")" = ".soul-switcher-backup" ] && rm -rf -- "$BACKUP_DIR"
  INSTALL_STARTED=0
  die "$message"
}

preserve_current_soul() {
  local candidate suffix
  [ -f "$HERMES_HOME_DIR/SOUL.md" ] || return 1
  for suffix in current current-before-soul-switcher; do
    candidate="$HERMES_HOME_DIR/souls/$suffix.md"
    if [ -f "$candidate" ] && [ ! -L "$candidate" ] && cmp -s "$HERMES_HOME_DIR/SOUL.md" "$candidate"; then
      say "Preserved current SOUL.md as souls/$suffix.md (already present)."
      return 0
    fi
    if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
      cp -p "$HERMES_HOME_DIR/SOUL.md" "$candidate"
      say "Preserved current SOUL.md as souls/$suffix.md."
      return 0
    fi
  done
  suffix=1
  while [ "$suffix" -le 999 ]; do
    candidate="$HERMES_HOME_DIR/souls/current-$suffix.md"
    if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
      cp -p "$HERMES_HOME_DIR/SOUL.md" "$candidate"
      say "Preserved current SOUL.md as souls/current-$suffix.md."
      return 0
    fi
    suffix=$((suffix + 1))
  done
  printf 'error: could not choose a safe filename for the current soul\n' >&2
  return 1
}

install_bundled_souls() {
  local source filename name target
  BUNDLED_DEFAULT=""

  for source in "$MOD_DIR"/souls/*.md; do
    [ -f "$source" ] || continue
    [ ! -L "$source" ] || die "bundled souls may not be symlinks: $source"

    filename="${source##*/}"
    name="${filename%.md}"
    [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] ||
      die "invalid bundled soul filename: $filename"

    target="$HERMES_HOME_DIR/souls/$filename"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      cp -- "$source" "$target"
      say "Installed bundled soul: $filename"
    fi

    if [ "$name" = "default" ] || [ -z "$BUNDLED_DEFAULT" ]; then
      BUNDLED_DEFAULT="$name"
    fi
  done
}

HERMES_DIR="$(locate_hermes "${1:-}")"
BACKUP_DIR="$HERMES_DIR/.soul-switcher-backup"

if [ -f "$BACKUP_DIR/installed" ]; then
  [ -f "$HERMES_DIR/$MODULE_FILE" ] || die "backup says installed, but $MODULE_FILE is missing"
  mkdir -p "$HERMES_HOME_DIR/souls"
  install_bundled_souls
  say "Hermes Soul Switcher is already installed. Bundled souls synchronized."
  exit 0
fi
[ ! -e "$BACKUP_DIR" ] || die "found an incomplete backup at $BACKUP_DIR; inspect it before retrying"

for rel in "${PATCHED_FILES[@]}"; do
  [ -f "$HERMES_DIR/$rel" ] || die "unsupported Hermes layout: missing $rel"
  [ -w "$HERMES_DIR/$rel" ] || die "cannot write $HERMES_DIR/$rel"
done
[ -w "$HERMES_DIR/hermes_cli" ] || die "cannot write $HERMES_DIR/hermes_cli"
command -v patch >/dev/null 2>&1 || die "the standard 'patch' utility is required"

if ! patch -d "$HERMES_DIR" -p1 --forward --batch --dry-run < "$MOD_DIR/soul-switcher.patch" >/dev/null; then
  die "this Hermes version does not match the included patch; no files were changed"
fi

trap cleanup_failed_install ERR
INSTALL_STARTED=1
mkdir -p "$BACKUP_DIR/original/hermes_cli" "$BACKUP_DIR/original/gateway" \
  "$BACKUP_DIR/original/tui_gateway" "$BACKUP_DIR/user"
for rel in "${PATCHED_FILES[@]}"; do
  cp -p "$HERMES_DIR/$rel" "$BACKUP_DIR/original/$rel"
done
if [ -e "$HERMES_DIR/$MODULE_FILE" ] || [ -L "$HERMES_DIR/$MODULE_FILE" ]; then
  cp -p "$HERMES_DIR/$MODULE_FILE" "$BACKUP_DIR/original/$MODULE_FILE"
else
  : > "$BACKUP_DIR/module-was-absent"
fi
if [ -e "$HERMES_HOME_DIR/SOUL.md" ] || [ -L "$HERMES_HOME_DIR/SOUL.md" ]; then
  cp -p "$HERMES_HOME_DIR/SOUL.md" "$BACKUP_DIR/user/SOUL.md"
else
  : > "$BACKUP_DIR/soul-was-absent"
fi
printf '%s\n' "$HERMES_HOME_DIR" > "$BACKUP_DIR/hermes-home"

if ! patch -d "$HERMES_DIR" -p1 --forward --batch < "$MOD_DIR/soul-switcher.patch" >/dev/null; then
  rollback_and_die "patch failed; original files were restored"
fi
if ! cp "$MOD_DIR/$MODULE_FILE" "$HERMES_DIR/$MODULE_FILE"; then
  rollback_and_die "module copy failed; original files were restored"
fi

PYTHON_BIN="$HERMES_DIR/venv/bin/python"
[ -x "$PYTHON_BIN" ] || PYTHON_BIN="$(command -v python3 2>/dev/null || true)"
if [ -z "$PYTHON_BIN" ] || ! "$PYTHON_BIN" -c \
  'import pathlib,sys; [compile(pathlib.Path(p).read_text(encoding="utf-8"), p, "exec") for p in sys.argv[1:]]' \
  "$HERMES_DIR/$MODULE_FILE" "${PATCHED_FILES[@]/#/$HERMES_DIR/}"; then
  rollback_and_die "syntax check failed; original files were restored"
fi

mkdir -p "$HERMES_HOME_DIR/souls"
install_bundled_souls
if [ -f "$HERMES_HOME_DIR/SOUL.md" ]; then
  preserve_current_soul
else
  [ -n "$BUNDLED_DEFAULT" ] || rollback_and_die "no bundled Markdown souls were found"
  cp "$HERMES_HOME_DIR/souls/$BUNDLED_DEFAULT.md" "$HERMES_HOME_DIR/SOUL.md"
  say "Created SOUL.md from souls/$BUNDLED_DEFAULT.md."
fi

printf '%s\n' "Hermes Soul Switcher" > "$BACKUP_DIR/installed"
INSTALL_STARTED=0
trap - ERR
say "Installed Hermes Soul Switcher in $HERMES_DIR"
say "Souls: $HERMES_HOME_DIR/souls"
say "Restart any running Hermes process once, then use /soul."
