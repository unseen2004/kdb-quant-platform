#!/usr/bin/env bash
# ============================================================================
# stop_stack.sh - Gracefully Stop All Running kdb+ Platform Processes
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -d pids ]; then
  echo "No pids/ directory found."
  exit 0
fi

for pidfile in pids/*.pid; do
  [ -e "$pidfile" ] || continue
  proc="$(basename "$pidfile" .pid)"
  pid="$(cat "$pidfile")"
  if kill -0 "$pid" 2>/dev/null; then
    echo "Stopping $proc (PID $pid)..."
    kill "$pid" || true
  fi
  rm -f "$pidfile"
done

echo "All kdb+ processes stopped."
