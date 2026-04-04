#!/bin/bash
echo "=== Setting up Custom Dark Theme Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Cleanup previous runs to ensure clean state
# Delete the theme directory if it exists
if [ -d "/var/www/html/upload/themes/survey/NightShiftDark" ]; then
    echo "Cleaning up existing theme..."
    rm -rf "/var/www/html/upload/themes/survey/NightShiftDark"
fi

# Delete the survey if it exists (via DB)
SURVEY_ID=$(get_survey_id "Night Shift Worker Experience")
if [ -n "$SURVEY_ID" ]; then
    echo "Cleaning up existing survey ID: $SURVEY_ID..."
    limesurvey_query "DELETE FROM lime_surveys WHERE sid=$SURVEY_ID"
    limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SURVEY_ID"
fi

# 2. Ensure LimeSurvey is ready and user is logged out or at login screen
# We rely on the agent to login (creds provided in description or standard admin/Admin123!)
# But for this task, let's assume standard admin credentials which are usually provided in the env description.
# We'll just make sure Firefox is open.

echo "Ensuring Firefox is running..."
focus_firefox
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
else
    # Navigate to admin home
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
    DISPLAY=:1 xdotool key Return
fi

# Wait for page load
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Agent needs to:"
echo "1. Create survey 'Night Shift Worker Experience'"
echo "2. Create theme 'NightShiftDark' (extending Fruity)"
echo "3. Edit custom.css (bg: #121212, color: #e0e0e0)"
echo "4. Apply theme to survey"