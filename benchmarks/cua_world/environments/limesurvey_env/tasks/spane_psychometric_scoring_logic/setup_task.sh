#!/bin/bash
echo "=== Setting up SPANE Psychometric Scoring Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready
wait_for_page_load 5
if ! curl -s http://localhost/index.php/admin > /dev/null; then
    echo "Waiting for LimeSurvey service..."
    sleep 10
fi

# Clean up any existing surveys with "Well-being" in title to ensure clean state
echo "Cleaning up previous surveys..."
limesurvey_query "DELETE FROM lime_surveys WHERE sid IN (SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Well-being%')" 2>/dev/null || true
limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Well-being%'" 2>/dev/null || true

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count
echo "Initial survey count: $INITIAL_COUNT"

# Ensure Firefox is running and focused
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "The agent must create a new survey from scratch."