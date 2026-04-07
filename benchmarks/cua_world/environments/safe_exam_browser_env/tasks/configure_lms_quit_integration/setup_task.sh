#!/bin/bash
set -e
echo "=== Setting up configure_lms_quit_integration task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/task_result.json /tmp/seb_dump.sql /tmp/task_start_screenshot.png /tmp/task_final.png 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline state of configurations
INITIAL_CONFIG_COUNT=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'" 2>/dev/null || echo "0")
echo "$INITIAL_CONFIG_COUNT" > /tmp/initial_config_count.txt

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server to set up the starting state
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot showing logged-in state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should create a new Exam Configuration named 'Biology Final - Moodle AutoQuit'."
echo "Must configure Quit URL and disable Confirm Quit."