#!/bin/bash
set -e
echo "=== Setting up task: activate_emergency_closure ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for DB to be responsive
echo "Waiting for database..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 1. Clean up previous task artifacts to ensure clean state
echo "Cleaning up DB..."
# Delete the target call time if it exists
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_call_times WHERE call_time_id='FORCE_CLOSE';"

# 2. Insert/Reset initial Inbound Group state (Open 24h)
# Ensure '24hours' call time exists (standard default)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT IGNORE INTO vicidial_call_times (call_time_id, call_time_name, call_time_comments, ct_default_start, ct_default_stop) 
VALUES ('24hours', '24 Hours - Open', 'Default 24 hours open', 0, 2400);"

# Reset CS_QUEUE to a known 'Open' state
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_inbound_groups WHERE group_id='CS_QUEUE';"
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
INSERT INTO vicidial_inbound_groups 
(group_id, group_name, active, group_color, call_time_id, after_hours_action, next_agent_call, queue_priority, after_hours_message_filename) 
VALUES 
('CS_QUEUE', 'Customer Service Queue', 'Y', 'blue', '24hours', 'HANGUP', 'longest_wait_all', '0', '');"

# 3. Setup Firefox
DISPLAY=:1 wmctrl -l
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_setup.log 2>&1 &"
    sleep 5
fi

# Ensure window is maximized
wait_for_window "firefox\|mozilla\|vicidial" 30
focus_firefox
maximize_active_window

# Navigate to Admin home to ensure clean start
navigate_to_url "${VICIDIAL_ADMIN_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="