#!/usr/bin/env bash
# Create a new session log file in this directory and print its path.
# Usage: ./.logs/new-session.sh [agent-name]
set -euo pipefail

agent="${1:-agent}"
ts="$(date -u +%Y-%m-%dT%H%M%SZ)"
# 6 hex chars from /dev/urandom
short="$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"

dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
file="${dir}/${ts}-${agent}-${short}.jsonl"

: >"$file"
# Seed with session-open marker so the file is never empty.
printf '{"ts":"%s","session":"%s-%s-%s","type":"note","agent":"%s","summary":"session opened"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ts" "$agent" "$short" "$agent" >>"$file"

echo "$file"
