#!/bin/bash
# Pre-task: launch Apple Notes and wait for its window to register.
# Idempotent — if already running, just wait. Mirrors the convention in
# 12_macos_environments.md and safari_env/tasks/launch_safari/setup_task.sh.
set -eu

if ! pgrep -x "Notes" >/dev/null; then
  echo "[pre_task] launching Notes"
  open -a Notes
fi

for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.Notes"'; then
    echo "[pre_task] Notes window registered after ${i}s"
    break
  fi
  sleep 1
done

# Brief settle for any startup chrome to lay out before screenshots.
sleep 2
