#!/bin/bash
echo "=== Exporting Submit Response Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get survey ID
SURVEY_ID=$(cat /tmp/task_survey_id 2>/dev/null || echo "")
INITIAL=$(cat /tmp/initial_response_count 2>/dev/null || echo "0")
CURRENT=$(get_response_count "$SURVEY_ID")

echo "Response count: initial=$INITIAL, current=$CURRENT"

# Debug: Check response table
echo ""
echo "=== DEBUG: Checking response table lime_survey_$SURVEY_ID ==="
limesurvey_query "SELECT * FROM lime_survey_$SURVEY_ID ORDER BY id DESC LIMIT 5" 2>/dev/null || echo "(table may not exist or empty)"
echo "=== END DEBUG ==="

# Check if a new response was submitted
FOUND="false"
RESPONSE_ID=""
SUBMIT_DATE=""
AGE_VALUE=""

if [ "$CURRENT" -gt "$INITIAL" ]; then
    FOUND="true"
    # Get the latest response with all fields
    RESPONSE_DATA=$(limesurvey_query "SELECT id, submitdate FROM lime_survey_$SURVEY_ID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$RESPONSE_DATA" ]; then
        RESPONSE_ID=$(echo "$RESPONSE_DATA" | awk '{print $1}')
        SUBMIT_DATE=$(echo "$RESPONSE_DATA" | awk '{print $2" "$3}')
        echo "Found new response: ID=$RESPONSE_ID, Submitted=$SUBMIT_DATE"

        # Get the age value from the numerical question column
        # The column name format is: surveyid X groupid X questionid
        # Find the column that contains the age value (last column typically)
        AGE_COLUMN=$(limesurvey_query "SHOW COLUMNS FROM lime_survey_$SURVEY_ID" 2>/dev/null | tail -1 | awk '{print $1}')
        if [ -n "$AGE_COLUMN" ]; then
            AGE_VALUE=$(limesurvey_query "SELECT \`$AGE_COLUMN\` FROM lime_survey_$SURVEY_ID WHERE id=$RESPONSE_ID" 2>/dev/null | head -1)
            echo "Age value from column $AGE_COLUMN: $AGE_VALUE"
        fi
    fi
fi

# Create JSON result
JSON_CONTENT=$(cat << EOF
{
    "survey_id": "$SURVEY_ID",
    "initial_response_count": $INITIAL,
    "current_response_count": $CURRENT,
    "response_submitted": $FOUND,
    "response": {
        "response_id": "$RESPONSE_ID",
        "submit_date": "$SUBMIT_DATE",
        "age_value": "$AGE_VALUE"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

export_json_result "$JSON_CONTENT" "/tmp/submit_response_result.json"

echo ""
cat /tmp/submit_response_result.json
echo ""
echo "=== Export Complete ==="
