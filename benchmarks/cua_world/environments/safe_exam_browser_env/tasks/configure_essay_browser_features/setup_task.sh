#!/bin/bash
echo "=== Setting up configure_essay_browser_features task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/baseline_config_count.txt /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record baseline counts for anti-gaming (detecting if a NEW config was actually made)
CONFIG_COUNT=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM configuration_node WHERE type='EXAM_CONFIG'" 2>/dev/null || echo "0")
echo "$CONFIG_COUNT" > /tmp/baseline_config_count.txt

# Launch Firefox and navigate to SEB Server
launch_firefox "http://localhost:8080"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should create the 'ENGL101_Creative_Writing_2026' Exam Configuration and toggle Browser features."