#!/bin/bash
set -e
echo "=== Setting up Team User Permissions Task ==="

source /workspace/scripts/task_utils.sh

# 1. CLEANUP: Remove any previous artifacts to ensure clean state
# We need to remove users and surveys that might match the task description
# to prevent false positives from previous runs.

echo "Cleaning up previous task artifacts..."

# Delete users if they exist
limesurvey_query "DELETE FROM lime_users WHERE users_name IN ('j.martinez', 'r.nakamura')" 2>/dev/null || true
limesurvey_query "DELETE FROM lime_permissions WHERE uid NOT IN (SELECT uid FROM lime_users)" 2>/dev/null || true

# Delete survey if it exists (by title match)
# First get SID
SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Consumer Brand Perception%' LIMIT 1" 2>/dev/null || echo "")
if [ -n "$SID" ]; then
    echo "Removing existing survey SID=$SID..."
    limesurvey_query "DELETE FROM lime_surveys WHERE sid=$SID" 2>/dev/null || true
    limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID" 2>/dev/null || true
    limesurvey_query "DELETE FROM lime_groups WHERE sid=$SID" 2>/dev/null || true
    limesurvey_query "DELETE FROM lime_questions WHERE sid=$SID" 2>/dev/null || true
    limesurvey_query "DELETE FROM lime_permissions WHERE entity_id=$SID AND entity='survey'" 2>/dev/null || true
fi

# 2. RECORD INITIAL STATE
# Timestamp for anti-gaming (users must be created AFTER this time)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial user count
INITIAL_USER_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_users" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt

# 3. PREPARE ENVIRONMENT
# Ensure Firefox is running and at login page
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
        echo "Firefox detected."
        DISPLAY=:1 wmctrl -a "Firefox"
        DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="