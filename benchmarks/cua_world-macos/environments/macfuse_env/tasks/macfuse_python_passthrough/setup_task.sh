#!/bin/bash
# pre_task hook for macfuse_python_passthrough.
#
# Responsibilities:
#   1. Clean slate: remove any pre-existing script, log, source dir, and
#      mount point so a do-nothing agent gets zero credit.
#   2. Ensure parent directories the agent will need exist:
#        ~/Documents/        (standard, but mkdir -p just in case)
#        ~/Volumes/          (user-level mount root; macOS doesn't ship one
#                             by default — only /Volumes/ which is root-owned)
#      Do NOT create ~/Volumes/watched_source/ itself — the agent must.
#   3. Record an authoritative task-start Unix timestamp so the verifier
#      can gate freshness on files mtime > task_start.
#   4. Launch Terminal so the agent has a CLI workspace (mirrors the
#      pre_task-launches-the-surface-app convention from
#      12_macos_environments.md — for macFUSE the surface is Terminal,
#      since macFUSE itself is a kernel framework with no UI window).
#   5. Best-effort start-state screenshot.
#
# Do NOT echo any expected content (script body, method names, etc.) —
# the agent is supposed to derive them.
set -eu

echo "=== Setting up macfuse_python_passthrough ==="

# 1) Clean slate.
rm -f  "$HOME/Documents/passthrough_fuse.py" 2>/dev/null || true
rm -f  "$HOME/Documents/fuse-access.log"      2>/dev/null || true
rm -rf "$HOME/Documents/source"               2>/dev/null || true
rm -rf "$HOME/Volumes/watched_source"         2>/dev/null || true
rm -rf "$HOME/Documents/__pycache__"          2>/dev/null || true

# 2) Ensure parent directories.
mkdir -p "$HOME/Documents"
mkdir -p "$HOME/Volumes"          # user-level mount root (not /Volumes/)
echo "[pre_task] parent dirs ready: ~/Documents and ~/Volumes"

# 3) Task-start Unix timestamp (seconds since epoch, macOS-portable).
date +%s > /tmp/macfuse_python_passthrough_task_start_timestamp
echo "task_start_unix=$(cat /tmp/macfuse_python_passthrough_task_start_timestamp)"

# 4) Launch Terminal (idempotent — skip if already running).
if ! pgrep -x Terminal >/dev/null; then
  echo "[pre_task] launching Terminal"
  open -a Terminal
fi

# Wait for the Terminal window to register so subsequent screencap captures
# something meaningful.
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qE '"Terminal"'; then
    echo "[pre_task] Terminal window registered after ${i}s"
    break
  fi
  sleep 1
done

# Settle so the Terminal prompt finishes painting.
sleep 3

# 5) Start-state screenshot (best-effort).
/usr/sbin/screencapture -x /tmp/macfuse_python_passthrough_task_start.png 2>/dev/null || true

echo "=== macfuse_python_passthrough setup complete ==="
echo "Terminal is running. Agent should pip-install mfusepy, set up directories, write the passthrough script, and confirm it compiles."
