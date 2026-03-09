#!/bin/bash
echo "=== Exporting Create Survey Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get counts
INITIAL=$(cat /tmp/initial_survey_count 2>/dev/null || echo "0")
CURRENT=$(get_survey_count)
echo "Survey count: initial=$INITIAL, current=$CURRENT"

# Debug: Show all surveys in database
echo ""
echo "=== DEBUG: All surveys in database ==="
limesurvey_query "SELECT surveyls_survey_id, surveyls_title FROM lime_surveys_languagesettings" 2>/dev/null || echo "(database query failed)"
echo "=== END DEBUG ==="

# Check for the expected survey (case-insensitive)
echo ""
echo "Checking for survey containing 'Customer Satisfaction Survey' (case-insensitive)..."
SURVEY_DATA=$(limesurvey_query "SELECT s.sid, sl.surveyls_title, s.datecreated, s.active
FROM lime_surveys s
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id
WHERE LOWER(sl.surveyls_title) LIKE LOWER('%customer%satisfaction%')
ORDER BY s.datecreated DESC
LIMIT 1")

FOUND="false"
SURVEY_ID=""
SURVEY_TITLE=""
SURVEY_CREATED=""
SURVEY_ACTIVE=""

if [ -n "$SURVEY_DATA" ]; then
    FOUND="true"
    SURVEY_ID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    # Handle multi-word title
    SURVEY_TITLE=$(echo "$SURVEY_DATA" | awk '{$1=""; $NF=""; $(NF-1)=""; print}' | sed 's/^ *//;s/ *$//')
    SURVEY_CREATED=$(echo "$SURVEY_DATA" | awk '{print $(NF-1)}')
    SURVEY_ACTIVE=$(echo "$SURVEY_DATA" | awk '{print $NF}')
    echo "Found survey: ID=$SURVEY_ID, Title=$SURVEY_TITLE"
else
    echo "Survey with 'customer satisfaction' not found"

    # Try broader search
    echo "Trying broader search for any new survey..."
    if [ "$CURRENT" -gt "$INITIAL" ]; then
        # Get the newest survey
        SURVEY_DATA=$(limesurvey_query "SELECT s.sid, sl.surveyls_title, s.datecreated, s.active
FROM lime_surveys s
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id
ORDER BY s.datecreated DESC
LIMIT 1")
        if [ -n "$SURVEY_DATA" ]; then
            FOUND="true"
            SURVEY_ID=$(echo "$SURVEY_DATA" | awk '{print $1}')
            SURVEY_TITLE=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SURVEY_ID LIMIT 1")
            SURVEY_CREATED=$(echo "$SURVEY_DATA" | awk '{print $(NF-1)}')
            SURVEY_ACTIVE=$(echo "$SURVEY_DATA" | awk '{print $NF}')
            echo "Found newest survey: ID=$SURVEY_ID, Title=$SURVEY_TITLE"
        fi
    fi
fi

# Get question count if survey found
QUESTION_COUNT=0
if [ -n "$SURVEY_ID" ]; then
    QUESTION_COUNT=$(get_question_count "$SURVEY_ID")
fi

# Create JSON result
JSON_CONTENT=$(cat << EOF
{
    "initial_survey_count": $INITIAL,
    "current_survey_count": $CURRENT,
    "survey_found": $FOUND,
    "survey": {
        "survey_id": "$SURVEY_ID",
        "title": "$SURVEY_TITLE",
        "created": "$SURVEY_CREATED",
        "active": "$SURVEY_ACTIVE",
        "question_count": $QUESTION_COUNT
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF
)

export_json_result "$JSON_CONTENT" "/tmp/create_survey_result.json"

echo ""
cat /tmp/create_survey_result.json
echo ""
echo "=== Export Complete ==="
