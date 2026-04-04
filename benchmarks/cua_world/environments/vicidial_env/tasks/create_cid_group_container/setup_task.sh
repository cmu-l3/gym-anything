#!/bin/bash
set -e
echo "=== Setting up task: create_cid_group_container ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Clean up any pre-existing container with this ID (clean state)
echo "Cleaning up any pre-existing CID_EAST_COAST container..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_settings_containers WHERE container_id='CID_EAST_COAST';" \
  2>/dev/null || true

# Record initial state (anti-gaming baseline)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_settings_containers WHERE container_id='CID_EAST_COAST';" \
  2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_container_count.txt

# Ensure the admin user (6666) has appropriate permissions
# User level 9 and admin_viewall needed to access Admin -> Settings Containers reliably
echo "Configuring user permissions..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "UPDATE vicidial_users SET user_level='9', modify_lists='1', modify_leads='1', modify_campaigns='1', admin_viewall='1', modify_servers='1' WHERE user='6666';" \
  2>/dev/null || true

# Kill any existing Firefox instances
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to the Vicidial admin page
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/vicidial/admin.php' > /tmp/firefox_task.log 2>&1 &"

# Wait for Firefox window
if wait_for_window "firefox\|mozilla\|vicidial" 30; then
    echo "Firefox window detected"
else
    echo "WARNING: Firefox window not detected"
fi

# Maximize and focus
sleep 3
maximize_active_window
focus_firefox

# Wait for page load
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="