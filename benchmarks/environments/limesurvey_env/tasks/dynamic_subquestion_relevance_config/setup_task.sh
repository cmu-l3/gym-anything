#!/bin/bash
echo "=== Setting up Dynamic Subquestion Relevance Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any existing surveys with the target name to ensure a fresh start
# This prevents the agent from editing an old version or the verifier finding stale data
EXISTING_SID=$(get_survey_id "New Hire IT Provisioning 2025")
if [ -n "$EXISTING_SID" ]; then
    echo "Removing existing survey (SID: $EXISTING_SID) to prepare fresh environment..."
    limesurvey_query "DELETE FROM lime_surveys WHERE sid=$EXISTING_SID"
    limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$EXISTING_SID"
    limesurvey_query "DELETE FROM lime_groups WHERE sid=$EXISTING_SID"
    limesurvey_query "DELETE FROM lime_questions WHERE sid=$EXISTING_SID"
    limesurvey_query "DROP TABLE IF EXISTS lime_survey_$EXISTING_SID"
fi

# Ensure Firefox is focused on LimeSurvey admin login
echo "Ensuring Firefox is focused on LimeSurvey..."
focus_firefox

# Navigate to LimeSurvey admin
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
echo "The agent should now:"
echo "1. Create 'New Hire IT Provisioning 2025' survey"
echo "2. Create 'DEPT' question (List) with SALES, ENG, LEGAL options"
echo "3. Create 'TOOLS' question (Multiple Choice) with subquestions"
echo "4. Apply relevance logic to subquestions based on DEPT selection"
echo "5. Activate survey"