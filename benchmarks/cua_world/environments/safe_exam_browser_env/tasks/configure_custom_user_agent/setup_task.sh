#!/bin/bash
set -e

echo "=== Setting up configure_custom_user_agent task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/task_final_screenshot.png 2>/dev/null || true

# Record task start time (for anti-gaming validation)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline counts to detect "do nothing"
record_baseline "configure_custom_user_agent" 2>/dev/null || true

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server using default credentials
login_seb_server "super-admin" "admin"
sleep 4

# Take initial screenshot showing logged-in state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should create config 'Engineering Legacy Final 2026' and set User Agent suffix to 'EngDept/LegacyAuth-v9'"