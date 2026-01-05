#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/Hello-Pork-Belly/hz-oneclick.git"
REPO_DIR="/opt/hz-oneclick"

log() { printf '%s\n' "$*" >&2; }

inside_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

ensure_repo_ready() {
  if [ -d "${REPO_DIR}/.git" ]; then
    cd "$REPO_DIR"
    git fetch --prune origin >/dev/null 2>&1 || true
    git checkout main >/dev/null 2>&1 || git checkout -b main origin/main >/dev/null 2>&1 || true
    git pull --ff-only origin main >/dev/null 2>&1 || true
    return 0
  fi

  if [ "$(id -u)" -eq 0 ]; then
    mkdir -p /opt
    rm -rf "$REPO_DIR"
    git clone "$REPO_URL" "$REPO_DIR"
  else
    if command -v sudo >/dev/null 2>&1; then
      sudo mkdir -p /opt
      sudo rm -rf "$REPO_DIR"
      sudo git clone "$REPO_URL" "$REPO_DIR"
    else
      log "ERROR: Need sudo/root to clone into ${REPO_DIR}."
      exit 1
    fi
  fi

  cd "$REPO_DIR"
  git checkout main >/dev/null 2>&1 || true
}

bootstrap_if_needed() {
  # Prevent infinite re-exec loops
  if [ "${HZ_BOOTSTRAPPED:-0}" = "1" ]; then
    return 0
  fi

  # If run via curl|bash, we are not in a git repo -> bootstrap to /opt/hz-oneclick
  if ! inside_git_repo; then
    log "[hz] Not inside a git repo. Bootstrapping to ${REPO_DIR} ..."
    ensure_repo_ready
    export HZ_BOOTSTRAPPED=1
    exec "${REPO_DIR}/hz.sh" "$@"
  fi

  # If inside a repo but not canonical path, prefer canonical
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ] && [ "$top" != "$REPO_DIR" ] && [ -f "${REPO_DIR}/hz.sh" ]; then
    log "[hz] Non-canonical repo path (${top}). Switching to ${REPO_DIR} ..."
    ensure_repo_ready
    export HZ_BOOTSTRAPPED=1
    exec "${REPO_DIR}/hz.sh" "$@"
  fi
}

main() {
  bootstrap_if_needed "$@"

  # Now we are in the repo; dispatch to repo entry.
  if [ -f "./lib/entry.sh" ]; then
    exec bash "./lib/entry.sh" "$@"
  fi

  if [ -f "./scripts/hz_entry.sh" ]; then
    exec bash "./scripts/hz_entry.sh" "$@"
  fi

  log "ERROR: No recognized entry script found."
  log "Checked: ./lib/entry.sh, ./scripts/hz_entry.sh"
  exit 1
}

main "$@"
