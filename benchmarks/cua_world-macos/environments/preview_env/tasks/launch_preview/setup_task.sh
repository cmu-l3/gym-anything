#!/bin/bash
# Pre-task: launch Preview and wait for its window to register.
# Idempotent — if already running, just wait. Mirrors the
# convention in 12_macos_environments.md.
set -eu

if ! pgrep -x "Preview" >/dev/null; then
  echo "[pre_task] launching Preview"
  open -a Preview
fi

for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qi "Preview"; then
    echo "[pre_task] Preview registered after ${i}s"
    break
  fi
  sleep 1
done

# Brief settle for any startup chrome to lay out before screenshots.
sleep 2
