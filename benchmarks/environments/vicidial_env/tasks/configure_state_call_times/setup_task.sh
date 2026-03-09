#!/bin/bash
set -e

echo "=== Setting up Configure State Call Times task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial services are running
vicidial_ensure_running

echo "Cleaning up any previous task data (Anti-Gaming)..."
# Delete the target records if they exist to ensure the agent creates them from scratch
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_call_times WHERE call_time_id IN ('FL_SAFE', 'NV_SAFE');" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_state_call_times WHERE state_call_time_id = 'US_STRICT_26';" 2>/dev/null || true

# Start Firefox and navigate to Admin Panel
# Vicidial usually has basic auth; we try to bypass or handle it by URL if possible, 
# but mostly we rely on the agent to log in. We pre-launch to the admin page.
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Wait for cleanup
sleep 2

su - ga -c "DISPLAY=:1 firefox 'http://localhost/vicidial/admin.php' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla" 30

# Maximize
maximize_active_window

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="