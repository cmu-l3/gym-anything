#!/bin/bash
echo "=== Setting up Cognitive Timed Assessment Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# Ensure LimeSurvey database is accessible
if ! mysqladmin -h limesurvey-db -u limesurvey -plimesurvey_pass ping > /dev/null 2>&1; then
    echo "Waiting for database..."
    sleep 5
fi

# Clean up any existing surveys with conflicting titles to ensure a clean start
# (In case the agent or previous runs left artifacts)
echo "Cleaning up old surveys..."
limesurvey_query "SELECT sid FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Executive Function%'" | while read sid; do
    if [ -n "$sid" ]; then
        echo "Deleting old survey SID: $sid"
        # We only delete the main entry, cascading delete usually handles the rest in a real DB, 
        # but for clean setup we mostly care about the title collision check in verification
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$sid"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$sid"
    fi
done

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "Initial survey count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/initial_survey_count.txt

# Ensure Firefox is running and focused
focus_firefox
# Navigate to Admin login if not already there
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="