#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=${DISPLAY:-:99}

if [ -x /workspace/hooks/pre_start.sh ]; then /workspace/hooks/pre_start.sh || true; fi

for i in {1..50}; do
  if command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

fluxbox > /tmp/fluxbox.log 2>&1 &
sleep 0.5
xclock > /tmp/xclock.log 2>&1 &
xterm -T "Preset X11" -e "echo 'Preset ready'; sleep 3600" > /tmp/xterm.log 2>&1 &

if [ -x /workspace/hooks/post_start.sh ]; then /workspace/hooks/post_start.sh || true; fi

