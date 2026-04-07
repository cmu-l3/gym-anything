#!/usr/bin/env bash
set -euo pipefail

# Ensure DISPLAY is set (DockerRunner sets DISPLAY=:99 and starts Xvfb)
export DISPLAY=${DISPLAY:-:99}

# Wait for X server readiness
for i in {1..50}; do
  if command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

# Start a lightweight WM and demo apps
fluxbox > /tmp/fluxbox.log 2>&1 &
sleep 0.5
xclock > /tmp/xclock.log 2>&1 &
xterm -T "GymAnything Example" -e "echo 'Example up. Press Ctrl+C to exit.'; sleep 3600" > /tmp/xterm.log 2>&1 &

echo "Started fluxbox, xclock, and xterm on $DISPLAY"

