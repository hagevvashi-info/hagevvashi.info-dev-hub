#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$HOME/$MDC_REPO_ROOT}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-1}"

EXCLUDE_FIND_PATHS=(
  "$REPO_ROOT/.git"
  "$REPO_ROOT/.vscode-server"
  "$REPO_ROOT/node_modules"
)

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

dump_path_details() {
  local path="$1"

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    log "path=$path state=missing"
    return 0
  fi

  log "path=$path"
  stat "$path" 2>/dev/null | sed 's/^/  /'
  if [[ -L "$path" ]]; then
    printf '  readlink: %s\n' "$(readlink "$path" 2>/dev/null || true)"
    printf '  readlink -f: %s\n' "$(readlink -f "$path" 2>/dev/null || true)"
  fi
}

snapshot_symlinks() {
  local find_args=("$REPO_ROOT")
  local exclude

  for exclude in "${EXCLUDE_FIND_PATHS[@]}"; do
    find_args+=(-path "$exclude" -prune -o)
  done

  find "${find_args[@]}" -type l -print0 2>/dev/null \
    | while IFS= read -r -d '' path; do
        local target stat_out
        target="$(readlink "$path" 2>/dev/null || true)"
        stat_out="$(stat -Lc 'inode=%i mode=%a uid=%u gid=%g mtime=%Y ctime=%Z' "$path" 2>/dev/null || true)"
        printf '%s\t%s\t%s\n' "$path" "$target" "$stat_out"
      done \
    | sort
}

dump_snapshot_diff() {
  local previous_file="$1"
  local current_file="$2"

  log 'symlink snapshot diff begin'
  diff -u "$previous_file" "$current_file" 2>/dev/null | sed 's/^/  /' || true
  log 'symlink snapshot diff end'
}

changed_paths_from_diff() {
  local previous_file="$1"
  local current_file="$2"

  diff -u "$previous_file" "$current_file" 2>/dev/null \
    | awk -F '\t' '
        /^--- / { next }
        /^\+\+\+ / { next }
        /^@@ / { next }
        /^[+-]/ {
          path = substr($1, 2)
          if (path ~ /^\//) {
            print path
          }
        }
      ' \
    | sort -u
}

dump_process_snapshot() {
  local patterns='code-server|@playwright/mcp|playwright-mcp|anthropic\.claude-code|openai\.chatgpt|github\.copilot-chat|/claude(| )|/codex(| )|codex app-server|Extension Host Process'
  local pids

  log 'process snapshot begin'
  ps -eo pid,ppid,lstart,cmd --sort=lstart \
    | grep -E "$patterns" \
    | grep -v 'grep -E' \
    | sed 's/^/  /' || true

  pids="$(
    ps -eo pid=,cmd= \
      | grep -E "$patterns" \
      | grep -v 'grep -E' \
      | awk '{print $1}'
  )"

  for pid in $pids; do
    if [[ -d "/proc/$pid" ]]; then
      printf '  pid=%s cwd=%s\n' "$pid" "$(readlink "/proc/$pid/cwd" 2>/dev/null || true)"
      printf '  pid=%s exe=%s\n' "$pid" "$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
    fi
  done

  log 'process snapshot end'
}

log "symlink watch started repo_root=$REPO_ROOT poll_interval=${POLL_INTERVAL_SECONDS}s"

STATE_DIR="$(mktemp -d /tmp/symlink-watch.XXXXXX)"
trap 'rm -rf "$STATE_DIR"' EXIT

LAST_SNAPSHOT_FILE="$STATE_DIR/last_snapshot.txt"
CURRENT_SNAPSHOT_FILE="$STATE_DIR/current_snapshot.txt"

snapshot_symlinks >"$LAST_SNAPSHOT_FILE"
log "initial symlink count=$(wc -l < "$LAST_SNAPSHOT_FILE")"

while true; do
  snapshot_symlinks >"$CURRENT_SNAPSHOT_FILE"
  if ! cmp -s "$LAST_SNAPSHOT_FILE" "$CURRENT_SNAPSHOT_FILE"; then
    log 'symlink change detected'
    dump_snapshot_diff "$LAST_SNAPSHOT_FILE" "$CURRENT_SNAPSHOT_FILE"

    while IFS=$'\t' read -r path _rest; do
      [[ -n "$path" ]] || continue
      dump_path_details "$path"
    done < <(
      changed_paths_from_diff "$LAST_SNAPSHOT_FILE" "$CURRENT_SNAPSHOT_FILE"
    )

    dump_process_snapshot
    mv "$CURRENT_SNAPSHOT_FILE" "$LAST_SNAPSHOT_FILE"
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done
