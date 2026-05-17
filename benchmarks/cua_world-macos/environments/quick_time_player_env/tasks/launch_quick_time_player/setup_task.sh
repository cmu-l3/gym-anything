#!/bin/bash
# Pre-task: launch QuickTime Player and wait for its bundle to register.
# Idempotent — if already running, just wait. Mirrors the
# convention in 12_macos_environments.md.
#
# Implementation notes:
#   - Process name is exactly "QuickTime Player" (with space). `pgrep -x` needs
#     the full quoted name; long-form process listing via `lsappinfo list`
#     reports the bundleID `com.apple.QuickTimePlayerX` which is what the
#     verifier grep keys on.
#   - `open -a "QuickTime Player"` resolves via LaunchServices regardless of
#     whether the bundle lives at /Applications or /System/Applications.
set -eu

if ! pgrep -x "QuickTime Player" >/dev/null; then
  echo "[pre_task] launching QuickTime Player"
  open -a "QuickTime Player"
fi

for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.QuickTimePlayerX"'; then
    echo "[pre_task] QuickTime Player registered after ${i}s"
    break
  fi
  sleep 1
done

# Brief settle for any startup chrome to lay out before screenshots.
sleep 2
