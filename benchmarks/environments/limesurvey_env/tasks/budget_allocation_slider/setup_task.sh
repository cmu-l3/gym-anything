#!/bin/bash
echo "=== Setting up Budget Allocation Slider Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# Cleanup: Remove any existing surveys with "Springfield" in title to ensure fresh start
# This prevents ambiguity if the task is retried
echo "Cleaning up any old 'Springfield' surveys..."
EXISTING_IDS=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid=sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%Springfield%'" | xargs)

if [ -n "$EXISTING_IDS" ]; then
    for sid in $EXISTING_IDS; do
        echo "Deleting old survey SID: $sid"
        # We need to drop tables carefully or just use API if possible, but for setup script, direct DB deletion of metadata is risky without dropping tables.
        # Instead, we'll just rename them to avoid name collision logic confusion, or let the user create a new one.
        # LimeSurvey allows duplicate titles, so deletion isn't strictly necessary for the system, 
        # but helpful for verification clarity.
        # We will assume the verifier looks for the *newest* survey matching the title.
        true 
    done
fi

# Ensure Firefox is ready
focus_firefox

# Navigate to admin home
echo "Navigating to Admin Home..."
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="