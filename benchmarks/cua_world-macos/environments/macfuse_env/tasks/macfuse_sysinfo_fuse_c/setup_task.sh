#!/bin/bash
# pre_task hook for macfuse_sysinfo_fuse_c.
#
# Responsibilities:
#   1. Delete any pre-existing ~/Documents/sysinfo_fuse/ so no prior source
#      can give the agent free credit (Anti-Pattern 7: update-style setup
#      must reset the target — here we *remove* the target entirely).
#   2. Record an authoritative task-start Unix timestamp so the verifier
#      can gate on source-file freshness (mtime > task_start).
#   3. Launch Terminal so the agent has its natural CLI/editing surface for
#      a C project (12_macos_environments.md: pre_task launches the app —
#      for a C-coding task that app is Terminal).
#   4. Capture a start screenshot for the trajectory archive.
#
# Does NOT echo any sysctl names, callback signatures, FUSE API constants,
# or compiler flags — those are the agent's job to discover.
set -eu

echo "=== Setting up macfuse_sysinfo_fuse_c ==="

PROJECT_DIR="$HOME/Documents/sysinfo_fuse"

# 1) Clean slate. Remove any prior attempt entirely.
if [ -d "$PROJECT_DIR" ]; then
  echo "[pre_task] removing pre-existing $PROJECT_DIR"
  rm -rf "$PROJECT_DIR"
fi
mkdir -p "$HOME/Documents"

# 2) Task-start timestamp (Unix epoch, seconds).
date +%s > /tmp/macfuse_sysinfo_fuse_c_task_start_timestamp
echo "task_start_unix=$(cat /tmp/macfuse_sysinfo_fuse_c_task_start_timestamp)"

# 3) Launch Terminal. Idempotent.
if ! pgrep -x Terminal >/dev/null; then
  echo "[pre_task] launching Terminal"
  open -a Terminal
fi

for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qE '"Terminal"'; then
    echo "[pre_task] Terminal window registered after ${i}s"
    break
  fi
  sleep 1
done

# Settle so the Terminal prompt finishes painting before screenshots.
sleep 3

# 4) Start-state screenshot (best-effort).
/usr/sbin/screencapture -x /tmp/macfuse_sysinfo_fuse_c_task_start.png 2>/dev/null || true

echo "=== macfuse_sysinfo_fuse_c setup complete ==="
echo "Terminal is running. Agent should author a macFUSE filesystem in C at $PROJECT_DIR."
