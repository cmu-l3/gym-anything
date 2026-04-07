#!/bin/bash
echo "=== Setting up configure_lms_setup task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/initial_lms_count.txt /tmp/initial_lms_ids.txt /tmp/task_result.json /tmp/task_start_screenshot.png /tmp/task_final.png 2>/dev/null || true

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record initial LMS setup count and IDs (Baseline)
echo "Recording baseline state..."
INITIAL_COUNT=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM lms_setup;" 2>/dev/null | tr -d '[:space:]' || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_lms_count.txt

docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT id FROM lms_setup;" 2>/dev/null > /tmp/initial_lms_ids.txt || echo "" > /tmp/initial_lms_ids.txt

# Launch Firefox and navigate to SEB Server login
launch_firefox "http://localhost:8080"
sleep 5

# Take initial screenshot of the starting state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should log in and create a new LMS Setup for Moodle."
echo "Baseline LMS Setup count: $INITIAL_COUNT"