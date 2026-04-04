#!/bin/bash
echo "=== Exporting Cascading Brand Exclusion Logic Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find the survey
SURVEY_ID=$(get_survey_id "Smartphone Brand Funnel")
SURVEY_FOUND="false"

if [ -n "$SURVEY_ID" ]; then
    SURVEY_FOUND="true"
    echo "Found survey ID: $SURVEY_ID"
else
    echo "Survey not found."
fi

# Helper function to get question info as JSON object
get_question_json() {
    local sid="$1"
    local title="$2"
    
    # Get QID and Type
    local q_data=$(limesurvey_query "SELECT qid, type FROM lime_questions WHERE sid=$sid AND title='$title' AND parent_qid=0")
    local qid=$(echo "$q_data" | awk '{print $1}')
    local type=$(echo "$q_data" | awk '{print $2}')
    
    if [ -z "$qid" ]; then
        echo "null"
        return
    fi

    # Get Attributes (filter and array_filter_exclude)
    local filter_attr=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$qid AND attribute='filter'" | tr -d '\n\r')
    local exclude_attr=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$qid AND attribute='array_filter_exclude'" | tr -d '\n\r')

    # Get Subquestion Codes (comma separated)
    # Using GROUP_CONCAT to get all subquestion codes in one string
    local sub_codes=$(limesurvey_query "SELECT GROUP_CONCAT(title ORDER BY question_order ASC SEPARATOR ',') FROM lime_questions WHERE parent_qid=$qid")

    # Construct JSON object
    cat <<EOF
{
    "qid": "$qid",
    "type": "$type",
    "filter_attr": "$filter_attr",
    "exclude_attr": "$exclude_attr",
    "sub_codes": "$sub_codes"
}
EOF
}

# Extract details for Q1, Q2, Q3
Q1_JSON="null"
Q2_JSON="null"
Q3_JSON="null"

if [ "$SURVEY_FOUND" == "true" ]; then
    Q1_JSON=$(get_question_json "$SURVEY_ID" "Q1_USE")
    Q2_JSON=$(get_question_json "$SURVEY_ID" "Q2_REJECT")
    Q3_JSON=$(get_question_json "$SURVEY_ID" "Q3_WHY")
fi

# Determine if survey is active
IS_ACTIVE="false"
if [ "$SURVEY_FOUND" == "true" ]; then
    ACTIVE_FLAG=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SURVEY_ID")
    if [ "$ACTIVE_FLAG" == "Y" ]; then
        IS_ACTIVE="true"
    fi
fi

# Create result JSON
cat > /tmp/task_result.json <<EOF
{
    "survey_found": $SURVEY_FOUND,
    "survey_id": "$SURVEY_ID",
    "is_active": $IS_ACTIVE,
    "q1": $Q1_JSON,
    "q2": $Q2_JSON,
    "q3": $Q3_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy to avoid permission issues if verified later
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json