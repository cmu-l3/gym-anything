#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_diagnostic_logging task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/seb_task_baseline_*.json /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Clean up any existing debug config from the database to ensure a clean state
echo "Cleaning up any pre-existing 'Engineering Basics - DEBUG' configurations..."
docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "DELETE FROM configuration_node WHERE name='Engineering Basics - DEBUG';" 2>/dev/null || true

# Record baseline
record_baseline "configure_diagnostic_logging" 2>/dev/null || true

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server automatically to save time for the agent
login_seb_server "super-admin" "admin"
sleep 4

# Take initial screenshot as evidence of starting state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should create a new Exam Configuration 'Engineering Basics - DEBUG' with specific debug settings."