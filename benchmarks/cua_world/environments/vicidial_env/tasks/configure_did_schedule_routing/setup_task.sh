#!/bin/bash
set -e

echo "=== Setting up Configure DID Schedule Routing Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# Wait for MySQL to be ready
echo "Waiting for Vicidial MySQL..."
for i in {1..30}; do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        echo "MySQL is ready"
        break
    fi
    sleep 2
done

# ==============================================================================
# DATA PREPARATION (Reset to known state)
# ==============================================================================

# 1. Clean up existing records to avoid duplicates/conflicts
echo "Cleaning up DB..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_inbound_dids WHERE did_pattern='8885559999';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_call_times WHERE call_time_id='9am-5pm';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_voicemail WHERE voicemail_id='8500';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_inbound_groups WHERE group_id='SUPPORT';" 2>/dev/null || true

# 2. Create 'SUPPORT' In-Group
echo "Creating In-Group SUPPORT..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT INTO vicidial_inbound_groups (group_id, group_name, active, group_color, next_agent_call) VALUES ('SUPPORT', 'General Support', 'Y', 'blue', 'longest_wait_time');"

# 3. Create Call Time '9am-5pm'
echo "Creating Call Time 9am-5pm..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT INTO vicidial_call_times (call_time_id, call_time_name, call_time_comments, ct_default_start, ct_default_stop) VALUES ('9am-5pm', '9am to 5pm Business Hours', 'Standard Business Hours', '0900', '1700');"

# 4. Create Voicemail Box '8500'
echo "Creating Voicemail 8500..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT INTO vicidial_voicemail (voicemail_id, extension, pass, fullname, active, delete_vm_after_email) VALUES ('8500', '8500', '1234', 'General Voicemail', 'Y', 'N');"

# 5. Create DID '8885559999' (Default configuration: 24hours, no filter)
echo "Creating DID 8885559999..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT INTO vicidial_inbound_dids (did_pattern, did_description, did_active, did_route, group_id, call_time_id, filter_action, filter_extension, filter_clean_cid_number) VALUES ('8885559999', 'Support Line Main', 'Y', 'INGROUP', 'SUPPORT', '24hours', 'NONE', '', 'N');"

# ==============================================================================
# BROWSER SETUP
# ==============================================================================

VICIDIAL_ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"
DID_PAGE_URL="${VICIDIAL_ADMIN_URL}?ADD=3311&did_pattern=8885559999"

echo "Launching Firefox..."
# Check if Firefox is running
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DID_PAGE_URL' > /dev/null 2>&1 &"
    sleep 5
fi

wait_for_window "firefox\|mozilla\|vicidial" 60

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Login Automation (if needed)
echo "Handling login..."
sleep 2
# Type username
DISPLAY=:1 xdotool type --delay 20 "6666"
DISPLAY=:1 xdotool key Tab
# Type password
DISPLAY=:1 xdotool type --delay 20 "andromeda"
DISPLAY=:1 xdotool key Return
sleep 5

# Ensure we are at the Inbound DIDs page
navigate_to_url "http://localhost/vicidial/admin.php?ADD=3311&did_pattern=8885559999"

# Capture initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="