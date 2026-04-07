#!/bin/bash
echo "=== Setting up configure_proctoring_features task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline for anti-gaming (tracks existing configs)
record_baseline "configure_proctoring_features"

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server via UI automation
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot showing clean starting state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should create Exam Configuration 'Distance Learning 101' and enable chat and retries"