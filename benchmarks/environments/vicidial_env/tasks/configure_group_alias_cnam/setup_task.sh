#!/bin/bash
set -e
echo "=== Setting up Configure Group Alias CNAM Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be ready
echo "Waiting for database..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Clean up any previous state to ensure a fair test
echo "Cleaning database state..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_group_aliases WHERE group_alias_id='RETENTION_HQ';" 2>/dev/null || true

# Ensure the target campaign exists, but reset its group alias setting
# Check if campaign exists
CAMP_EXISTS=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_campaigns WHERE campaign_id='RETENTION';" 2>/dev/null || echo "0")

if [ "$CAMP_EXISTS" -eq "0" ]; then
    echo "Creating RETENTION campaign..."
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT INTO vicidial_campaigns (campaign_id, campaign_name, active, dial_method, auto_dial_level, lead_order, campaign_cid) VALUES ('RETENTION', 'Customer Retention', 'Y', 'MANUAL', '0', 'DOWN', '0000000000');"
else
    echo "Resetting RETENTION campaign settings..."
    docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "UPDATE vicidial_campaigns SET default_group_alias='' WHERE campaign_id='RETENTION';"
fi

# Record initial count of aliases (anti-gaming)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_group_aliases;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_alias_count.txt

# Launch Firefox to Vicidial Admin
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Use standard admin URL
ADMIN_URL="http://localhost/vicidial/admin.php"
su - ga -c "DISPLAY=:1 firefox '$ADMIN_URL' > /dev/null 2>&1 &"

# Wait for Firefox
wait_for_window "Firefox\|Mozilla\|Vicidial" 60

# Maximize
maximize_active_window
sleep 1

# Handle Login (Standard Vicidial credentials: 6666 / andromeda)
# The environment often requires Basic Auth interaction or Form interaction depending on config.
# We'll blindly attempt to type credentials if we see the login screen or auth dialog.
echo "Handling potential login..."
sleep 5
DISPLAY=:1 xdotool type --delay 50 "6666" 2>/dev/null || true
DISPLAY=:1 xdotool key Tab 2>/dev/null || true
DISPLAY=:1 xdotool type --delay 50 "andromeda" 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Wait for page load
sleep 5

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="