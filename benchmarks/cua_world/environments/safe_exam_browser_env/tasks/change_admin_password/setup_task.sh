#!/bin/bash
echo "=== Setting up change_admin_password task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Clean up stale temp files from previous runs
sudo rm -f /tmp/task_start_time.txt /tmp/initial_admin_hash.txt /tmp/*_result.json /tmp/task_start_screenshot.png /tmp/final_screenshot.png 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure SEB Server is accessible
wait_for_seb_server 120

# Record the initial password hash for anti-gaming (to ensure it actually changes)
echo "Recording baseline password hash..."
INITIAL_HASH=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT password FROM user WHERE username='super-admin';" 2>/dev/null || echo "unknown")
echo "$INITIAL_HASH" > /tmp/initial_admin_hash.txt

# Launch Firefox and navigate to SEB Server login page
launch_firefox "${SEB_SERVER_URL}"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should log in and update the super-admin profile and password."