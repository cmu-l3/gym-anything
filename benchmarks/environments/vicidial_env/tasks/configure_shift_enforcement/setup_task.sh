#!/bin/bash
set -e
echo "=== Setting up Configure Shift Enforcement task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Vicidial is running
vicidial_ensure_running

# 2. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Prepare Database State (Clean Slate)
# We need to ensure the shift does NOT exist and the group exists but has no enforcement.

echo "Preparing Vicidial database state..."
# Delete the shift if it exists
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_shifts WHERE shift_id='SURVEY_EVE';" 2>/dev/null || true

# Reset the SURVEY user group (create if missing, reset if exists)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_user_groups WHERE user_group='SURVEY';" 2>/dev/null || true

docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "INSERT INTO vicidial_user_groups (user_group, group_name, shift_enforcement, group_shifts, forced_timecheck_lifespan) VALUES ('SURVEY', 'Survey Team', 'OFF', '', 'disabled');"

# Ensure Admin User 6666 has permissions to view/modify Shifts and User Groups
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "UPDATE vicidial_users SET modify_shifts='1', modify_user_groups='1', user_level='9', view_reports='1' WHERE user='6666';"

# 4. Launch Browser to Admin Interface
# Use the direct admin URL
START_URL="${VICIDIAL_ADMIN_URL}"

# Kill any existing firefox
pkill -f firefox 2>/dev/null || true

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '${START_URL}' > /dev/null 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 60
focus_firefox
maximize_active_window

# Authenticate if needed (Vicidial basic auth)
# The environment often prompts for Basic Auth. We type it in blindly just in case.
sleep 3
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="