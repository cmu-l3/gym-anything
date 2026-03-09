#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=${DISPLAY:-:99}

# Wait for Xvfb
for i in {1..50}; do
  if command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

# Simple WM
fluxbox > /tmp/fluxbox.log 2>&1 &
sleep 0.5

# Launch Chromium in fullscreen with a blank page, remote debugging enabled
chromium-browser --no-sandbox --disable-gpu --start-fullscreen --remote-debugging-port=9222 about:blank \
  >/tmp/chrome.log 2>&1 &
echo "Chromium started on $DISPLAY"

