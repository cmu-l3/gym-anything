#!/bin/bash
set -e
echo "=== Setting up Implement After-Hours Routing task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial services are running
vicidial_ensure_running

echo "Resetting database state..."
# 1. Remove the target Call Time if it exists (ensure clean slate)
# 2. Reset the Inbound Group PRISUP to a default state (24hours, MESSAGE action)
# 3. Ensure Voicemail 1000 exists (insert into phones/vicidial_voicemail if needed)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "
    DELETE FROM vicidial_call_times WHERE call_time_id='PRISUP_HRS';
    DELETE FROM vicidial_inbound_groups WHERE group_id='PRISUP';
    
    INSERT INTO vicidial_inbound_groups (group_id, group_name, active, group_color, call_time_id, after_hours_action, after_hours_message, after_hours_voicemail)
    VALUES ('PRISUP', 'Priority Support', 'Y', 'red', '24hours', 'MESSAGE', 'vm-goodbye', '');
    
    INSERT IGNORE INTO vicidial_voicemail (voicemail_id, pass, name, active, mail_boxes) 
    VALUES ('1000', '1000', 'General Mailbox', 'Y', '1000');
"

# Launch Firefox to Admin Panel
# Use credentials in URL or let agent log in. Task description gives credentials.
# We'll start at the login screen or admin dashboard if session persists.
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "Vicidial" 60 || echo "WARNING: Vicidial window not detected"

# Maximize
maximize_active_window

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="