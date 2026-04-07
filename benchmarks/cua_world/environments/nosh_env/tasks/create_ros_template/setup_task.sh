#!/bin/bash
# Setup script for create_ros_template task

echo "=== Setting up Create ROS Template Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# CLEANUP: Remove any existing template with the target name
# This ensures the agent must actually create it, not just find an existing one.
# ==============================================================================
echo "Cleaning up any existing 'Cardio_Consult' templates..."
# We use a broad delete approach since we might not know the exact table schema for templates
# but we can try to find where it might be stored or just rely on the agent creating a new ID.
# Since deleting complex relational data blindly is risky, we will rely on the 
# verification checking for a CREATION time or ID > initial max ID, 
# but specifically for text based templates, we'll try to delete if we can identify the table.
#
# For NOSH, form layouts/templates often live in `form_layout` or similar tables.
# To be safe, we will rely on checking the DATABASE STATE CHANGE in the export script,
# ensuring the record appears *after* the task starts.

# Record initial database state hash/snapshot to detect changes
echo "Recording initial database state..."
docker exec nosh-db mysqldump -uroot -prootpassword nosh > /tmp/nosh_initial_dump.sql 2>/dev/null
grep -i "Cardio_Consult" /tmp/nosh_initial_dump.sql > /tmp/initial_template_check.txt || true

# ==============================================================================
# APPLICATION SETUP
# ==============================================================================

# Kill any existing Firefox instances to ensure clean session
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean Firefox locks
rm -f /home/ga/.mozilla/firefox/*.default-release/lock 2>/dev/null || true
rm -f /home/ga/.mozilla/firefox/*.default-release/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*.default/lock 2>/dev/null || true

# Start Firefox at the login page
echo "Starting Firefox..."
NOSH_URL="http://localhost/login"

if snap list firefox &>/dev/null 2>&1; then
    # Snap firefox
    su - ga -c "DISPLAY=:1 setsid /snap/bin/firefox --new-instance '$NOSH_URL' > /tmp/firefox_task.log 2>&1 &"
else
    # Native firefox
    su - ga -c "DISPLAY=:1 setsid firefox '$NOSH_URL' > /tmp/firefox_task.log 2>&1 &"
fi

# Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh"; then
        echo "Firefox detected."
        break
    fi
    sleep 1
done

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="