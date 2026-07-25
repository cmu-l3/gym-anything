#!/bin/bash
# pre_task hook for audit_macfuse_install.
#
# Responsibilities:
#   1. Delete any pre-existing report so a do-nothing agent can't get credit.
#   2. Record an authoritative task-start Unix timestamp so the verifier can
#      gate on report freshness (mtime > task_start).
#   3. Launch Terminal so the agent has a CLI workspace to run audit commands
#      (consistent with the pre_task-launches-the-app convention from
#      12_macos_environments.md). Do NOT echo any ground-truth values — the
#      whole point is for the agent to discover them.
set -eu

echo "=== Setting up audit_macfuse_install ==="

# 1) Clean slate
rm -f "$HOME/Documents/macfuse_audit_report.json" 2>/dev/null || true
mkdir -p "$HOME/Documents"

# 2) Task-start timestamp (Unix epoch, seconds)
date +%s > /tmp/macfuse_audit_task_start_timestamp
echo "task_start_unix=$(cat /tmp/macfuse_audit_task_start_timestamp)"

# 3) Launch Terminal. Idempotent — if already running, skip the open.
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

# Settle: let the Terminal window's prompt finish painting before screenshots.
sleep 3

# Start-state screenshot for the trajectory archive (best-effort).
/usr/sbin/screencapture -x /tmp/macfuse_audit_task_start.png 2>/dev/null || true

echo "=== audit_macfuse_install setup complete ==="
echo "Terminal is running. Agent should audit the installed macFUSE framework and write the JSON report."
