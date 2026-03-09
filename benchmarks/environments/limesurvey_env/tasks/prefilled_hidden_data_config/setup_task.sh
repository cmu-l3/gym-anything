#!/bin/bash
echo "=== Setting up Prefilled Hidden Data Configuration Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# Clear any existing surveys with conflicting names to ensure clean state
# This prevents the verifier from picking up an old/wrong survey
EXISTING_SIDS=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid=sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%Employee Engagement Pulse%'")

if [ -n "$EXISTING_SIDS" ]; then
    echo "Cleaning up existing matching surveys..."
    for SID in $EXISTING_SIDS; do
        # We can't easily delete via SQL safely due to foreign keys, 
        # but we can rename them to avoid confusion or accept that the agent might edit them.
        # Ideally, we rely on the agent creating a NEW one or we'd delete via API.
        # For this environment, we'll log it.
        echo "Warning: Survey $SID already exists with similar title."
    done
fi

# Ensure Firefox is focused on LimeSurvey admin
focus_firefox

# Navigate to LimeSurvey admin
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="