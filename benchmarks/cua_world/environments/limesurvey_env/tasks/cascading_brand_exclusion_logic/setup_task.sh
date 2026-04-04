#!/bin/bash
echo "=== Setting up Cascading Brand Exclusion Logic Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any existing survey with the target title to ensure a clean start
echo "Cleaning up existing surveys..."
SURVEY_ID=$(get_survey_id "Smartphone Brand Funnel")
if [ -n "$SURVEY_ID" ]; then
    echo "Removing existing survey ID: $SURVEY_ID"
    limesurvey_query "DELETE FROM lime_surveys WHERE sid=$SURVEY_ID"
    limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SURVEY_ID"
    limesurvey_query "DELETE FROM lime_questions WHERE sid=$SURVEY_ID"
    limesurvey_query "DELETE FROM lime_groups WHERE sid=$SURVEY_ID"
    limesurvey_query "DELETE FROM lime_answers WHERE qid IN (SELECT qid FROM lime_questions WHERE sid=$SURVEY_ID)"
    limesurvey_query "DROP TABLE IF EXISTS lime_survey_$SURVEY_ID"
fi

# Ensure LimeSurvey is running and reachable
wait_for_limesurvey || echo "WARNING: LimeSurvey might not be fully ready"

# Ensure Firefox is focused on LimeSurvey admin
focus_firefox
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="