#!/bin/bash
echo "=== Setting up login_and_navigate_to_servers task ==="

source /workspace/scripts/task_utils.sh

if ! wait_for_cmdbuild 240; then
  echo "ERROR: CMDBuild is not reachable"
  exit 1
fi

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Start from clean browser session pointing at login page
restart_firefox "$CMDBUILD_URL"

# Wait for the login page to fully render before handing off to the agent
if ! wait_for_rendered_browser_view /tmp/task_start_screenshot.png 60; then
  echo "WARNING: Browser view did not stabilize before timeout"
fi

echo "=== Task setup complete ==="
echo "Credentials: admin / admin"
echo "Goal: login and navigate to Server CI list"
