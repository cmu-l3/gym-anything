#!/bin/bash
echo "=== Setting up Submit Response task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Find the Customer Satisfaction Survey
SURVEY_ID=$(get_survey_id "Customer Satisfaction")
if [ -z "$SURVEY_ID" ]; then
    echo "WARNING: No 'Customer Satisfaction Survey' found in database."
    echo "The agent will need to create the survey and activate it first."
    SURVEY_ID="unknown"
    echo "0" > /tmp/initial_response_count
else
    echo "Found existing survey ID: $SURVEY_ID"

    # Check if survey is active
    ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SURVEY_ID")
    if [ "$ACTIVE" != "Y" ]; then
        echo "WARNING: Survey is not active. Agent must activate it through the UI."
    else
        echo "Survey is active."
    fi

    # Try to get response count (may fail if response table doesn't exist)
    INITIAL_RESPONSE_COUNT=$(get_response_count "$SURVEY_ID")
    echo "Initial response count: $INITIAL_RESPONSE_COUNT"
    echo "$INITIAL_RESPONSE_COUNT" > /tmp/initial_response_count
fi

echo "$SURVEY_ID" > /tmp/task_survey_id

# Take screenshot of initial state
take_screenshot /tmp/task_start_screenshot.png

# Focus Firefox
echo ""
echo "Ensuring Firefox is focused on LimeSurvey..."
focus_firefox

# Navigate to LimeSurvey admin
DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
DISPLAY=:1 xdotool key Return
sleep 3

echo ""
echo "=== Task Setup Complete ==="
echo "The agent should now:"
echo "1. Login to LimeSurvey if not logged in (admin / Admin123!)"
echo "2. Navigate to the 'Customer Satisfaction Survey'"
echo "3. Activate the survey if not active (through Activate survey button)"
echo "4. Navigate to the survey URL to take the survey"
echo "5. Fill out the survey with age: 35"
echo "6. Submit the response"
