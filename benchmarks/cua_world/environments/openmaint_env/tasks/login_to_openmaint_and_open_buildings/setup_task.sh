#!/bin/bash
set -e

echo "=== Setting up login_to_openmaint_and_open_buildings task ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_openmaint 240; then
  echo "ERROR: OpenMaint is not reachable"
  exit 1
fi

# Start each episode from a clean browser session to keep task start deterministic.
pkill -f firefox || true
sleep 1

su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_task_openmaint.log 2>&1 &"

if ! wait_for_window "firefox|mozilla|openmaint|cmdbuild" 40; then
  echo "WARNING: Firefox window not detected"
fi

focus_firefox || true

# Force navigation once more and wait for the login UI to render.
su - ga -c "DISPLAY=:1 xdotool key ctrl+l"
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --delay 20 '$OPENMAINT_URL'"
su - ga -c "DISPLAY=:1 xdotool key Return"

if ! wait_for_rendered_browser_view /tmp/task_start_screenshot.png 60; then
  echo "WARNING: Browser view did not stabilize before timeout; captured best-effort screenshot"
fi

echo "=== Task setup complete ==="
echo "Credentials: admin / admin"
echo "Goal: login and open Buildings list with demo building records visible"
