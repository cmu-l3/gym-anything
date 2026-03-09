#!/bin/bash
echo "=== Setting up Create Survey task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record initial state
INITIAL_COUNT=$(get_survey_count)
echo "Initial survey count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# List existing surveys
echo ""
echo "Existing surveys:"
limesurvey_query "SELECT sid, surveyls_title FROM lime_surveys_languagesettings LIMIT 10" 2>/dev/null || echo "(database not ready or no surveys)"

# Take screenshot of initial state
take_screenshot /tmp/task_start_screenshot.png

# Ensure Firefox is focused on LimeSurvey admin
echo ""
echo "Ensuring Firefox is focused on LimeSurvey..."
focus_firefox
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -i -E "(firefox|limesurvey|mozilla)" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    echo "Window focused: $WINDOW_ID"
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID"
    echo "Firefox window focused"
else
    echo "WARNING: Firefox window not found"
fi

echo ""
echo "=== Task Setup Complete ==="
echo "The agent should now:"
echo "1. Login to LimeSurvey if not logged in (admin / Admin123!)"
echo "2. Click 'Create survey' button"
echo "3. Enter survey title: 'Customer Satisfaction Survey'"
echo "4. Click 'Save' to create the survey"
