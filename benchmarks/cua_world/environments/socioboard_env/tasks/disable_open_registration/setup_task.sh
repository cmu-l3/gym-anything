#!/bin/bash
set -e
echo "=== Setting up disable_open_registration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Wait for Socioboard frontend to be ready
if ! wait_for_http "http://localhost/login" 120; then
  echo "ERROR: Socioboard not reachable at http://localhost/login"
  exit 1
fi

# Ensure git is set up to track agent's modifications securely
echo "Setting up git tracking in codebase..."
cd /opt/socioboard/socioboard-web-php
git config --global --add safe.directory "*"

# Create a clean baseline tag to compare against later
git tag -d task_start_state 2>/dev/null || true
git add .
git commit -m "pre-task baseline" 2>/dev/null || true
git tag task_start_state

# Clear any previous run artifacts
sudo rm -f /tmp/task_start.png /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

# Launch Firefox and navigate to login page
echo "Launching Firefox..."
open_socioboard_page "http://localhost/login"
sleep 3

# Take initial screenshot showing the original login page
take_screenshot /tmp/task_start.png

echo "=== Task setup complete: disable_open_registration ==="