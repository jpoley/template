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

# GitHub Copilot CLI (standalone agentic CLI, npm package @github/copilot).
# Provides the `copilot` command. Auth happens on first run via `/login`.
if ! have copilot; then
  if have npm; then
    log "installing GitHub Copilot CLI (@github/copilot)"
    npm install -g @github/copilot || log "@github/copilot install failed (non-fatal)"
  else
    log "npm not available — skipping GitHub Copilot CLI"
  fi
else
  log "copilot already present: $(copilot --version 2>/dev/null | head -1)"
fi

# gh CLI presence check. gh itself is provided by the devcontainer feature
# or the host package manager.
if ! have gh; then
  log "gh CLI not installed — install via 'sudo apt install gh' or your package manager"
fi
