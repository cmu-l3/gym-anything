#!/bin/bash
echo "=== Setting up Add Question task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# This task requires a survey to already exist
# The agent must create the survey through the UI as part of this task if it doesn't exist
SURVEY_ID=$(get_survey_id "Customer Satisfaction")
if [ -z "$SURVEY_ID" ]; then
    echo "WARNING: No 'Customer Satisfaction Survey' found in database."
    echo "The agent will need to create the survey first, then add a question."
    SURVEY_ID="unknown"
    echo "0" > /tmp/initial_question_count
else
    echo "Found existing survey ID: $SURVEY_ID"
    # Record initial question count
    INITIAL_QUESTION_COUNT=$(get_question_count "$SURVEY_ID")
    echo "Initial question count: $INITIAL_QUESTION_COUNT"
    echo "$INITIAL_QUESTION_COUNT" > /tmp/initial_question_count
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
echo "2. Navigate to or create 'Customer Satisfaction Survey'"
echo "3. Click 'Add question'"
echo "4. Set question code: 'QAGE'"
echo "5. Enter question text: 'What is your age?'"
echo "6. Select question type: 'Numerical input'"
echo "7. Save the question"
