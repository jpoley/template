#!/usr/bin/env bash
# Install per-project CLI tools.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/_common.sh"

# backlog.md — project management CLI
if ! have backlog; then
  log "installing backlog.md"
  npm install -g backlog.md
else
  log "backlog already present: $(backlog --version)"
fi

# Claude Code CLI (official installer)
if ! have claude; then
  log "installing Claude Code CLI"
  curl -fsSL https://claude.ai/install.sh | bash || npm install -g @anthropic-ai/claude-code
else
  log "claude already present"
fi

# GitHub Copilot CLI as a gh extension. Requires gh authenticated; skip silently otherwise.
if have gh; then
  if ! gh extension list 2>/dev/null | grep -q 'github/gh-copilot'; then
    log "installing gh copilot extension"
    gh extension install github/gh-copilot || log "gh copilot install failed (need gh auth login first)"
  fi
else
  log "gh CLI not installed — install via 'sudo apt install gh' or your package manager"
fi
