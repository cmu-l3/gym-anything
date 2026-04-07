#!/bin/bash
echo "=== Setting up schedule_and_activate_exam task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files
sudo rm -f /tmp/task_start_time.txt /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Rename an existing exam/config to our target so the agent has a starting object to edit
echo "Setting up target exam..."
docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "
UPDATE exam SET name='CS101 - Algorithms Final', status='DRAFT' LIMIT 1;
" 2>/dev/null || true

docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "
UPDATE configuration_node SET name='CS101 - Algorithms Final' WHERE type='EXAM_CONFIG' LIMIT 1;
" 2>/dev/null || true

# Launch Firefox and navigate to SEB Server
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Login to SEB Server
login_seb_server "super-admin" "admin"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="