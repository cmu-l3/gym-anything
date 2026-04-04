#!/bin/bash
set -e
echo "=== Setting up Age-Based Logic Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# Ensure LimeSurvey is ready
if ! wait_for_limesurvey_api 2>/dev/null; then
    echo "Waiting for LimeSurvey to stabilize..."
    sleep 10
fi

# Cleanup: Remove any previous attempts at this survey to ensure clean state
# We look for surveys with "Influenza" or "Vaccine" in the title
echo "Cleaning up previous attempts..."
SURVEY_IDS=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE LOWER(surveyls_title) LIKE '%influenza%' OR LOWER(surveyls_title) LIKE '%vaccine%'")
for SID in $SURVEY_IDS; do
    if [ -n "$SID" ]; then
        echo "Removing stale survey ID: $SID"
        limesurvey_query "DELETE FROM lime_surveys WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID"
        limesurvey_query "DELETE FROM lime_groups WHERE sid=$SID"
        limesurvey_query "DELETE FROM lime_questions WHERE sid=$SID"
    fi
done

# Ensure Firefox is running and focused
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 10
fi

# Focus the window
focus_firefox
maximize_window "Firefox"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Agent is ready to create 'Influenza Vaccine Study Screener 2026'"