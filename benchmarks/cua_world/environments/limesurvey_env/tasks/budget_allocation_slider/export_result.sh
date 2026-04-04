#!/bin/bash
echo "=== Exporting Budget Allocation Slider Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Find the target survey (looking for newest one with correct title)
SURVEY_TITLE_PATTERN="Springfield%2026%Budget"
SURVEY_DATA=$(limesurvey_query "SELECT s.sid, sl.surveyls_title, s.active 
    FROM lime_surveys s 
    JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
    WHERE sl.surveyls_title LIKE '%Springfield%' 
    ORDER BY s.datecreated DESC LIMIT 1" 2>/dev/null)

FOUND="false"
SID=""
TITLE=""
ACTIVE="N"

if [ -n "$SURVEY_DATA" ]; then
    FOUND="true"
    SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    # Extract title (columns 2 to N-1)
    TITLE=$(echo "$SURVEY_DATA" | cut -f2)
    ACTIVE=$(echo "$SURVEY_DATA" | awk '{print $NF}')
    echo "Found Survey: SID=$SID, Title='$TITLE', Active=$ACTIVE"
else
    echo "Survey not found."
fi

# 2. Get Question Details
BUDGET_QID=""
BUDGET_TYPE=""
BUDGET_SETTINGS=""
REASON_QID=""
REASON_RELEVANCE=""

SUB_QUESTIONS_JSON="[]"

if [ "$FOUND" = "true" ]; then
    # Find BUDGET question (Type K = Multiple Numerical Input)
    BUDGET_DATA=$(limesurvey_query "SELECT qid, type FROM lime_questions WHERE sid=$SID AND title='BUDGET' AND parent_qid=0" 2>/dev/null)
    BUDGET_QID=$(echo "$BUDGET_DATA" | awk '{print $1}')
    BUDGET_TYPE=$(echo "$BUDGET_DATA" | awk '{print $2}')
    
    if [ -n "$BUDGET_QID" ]; then
        # Get Attributes for BUDGET (slider_layout, equals_num_value)
        # slider_layout is often 1 for yes
        # equals_num_value should be 100
        slider_attr=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$BUDGET_QID AND attribute='slider_layout'" 2>/dev/null)
        sum_attr=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$BUDGET_QID AND attribute='equals_num_value'" 2>/dev/null)
        
        # Get subquestions
        # We want to check if SAFE, INFRA, PARK, HLTH, GOV exist
        SUB_Q_TITLES=$(limesurvey_query "SELECT title FROM lime_questions WHERE parent_qid=$BUDGET_QID ORDER BY question_order" 2>/dev/null)
        # Convert newlines to JSON array
        SUB_QUESTIONS_JSON=$(echo "$SUB_Q_TITLES" | jq -R -s -c 'split("\n")[:-1]')
    fi

    # Find REASON question and its relevance
    REASON_DATA=$(limesurvey_query "SELECT qid, relevance FROM lime_questions WHERE sid=$SID AND title='REASON'" 2>/dev/null)
    REASON_QID=$(echo "$REASON_DATA" | awk '{print $1}')
    # Relevance can contain spaces, take everything after first column
    REASON_RELEVANCE=$(echo "$REASON_DATA" | cut -f2-)
fi

# Create JSON result
JSON_FILE="/tmp/budget_task_result.json"

# Use python to safely construct JSON to handle potential quoting issues in relevance equations
python3 -c "
import json
import sys

data = {
    'survey_found': '$FOUND' == 'true',
    'sid': '$SID',
    'title': '''$TITLE''',
    'active': '$ACTIVE',
    'budget_question': {
        'found': '$BUDGET_QID' != '',
        'qid': '$BUDGET_QID',
        'type': '$BUDGET_TYPE',
        'slider_layout': '''$slider_attr'''.strip(),
        'equals_sum_value': '''$sum_attr'''.strip(),
        'sub_questions': $SUB_QUESTIONS_JSON
    },
    'reason_question': {
        'found': '$REASON_QID' != '',
        'qid': '$REASON_QID',
        'relevance': '''$REASON_RELEVANCE'''.strip()
    }
}

with open('$JSON_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"

# Handle permissions
chmod 666 "$JSON_FILE"

echo "Export complete. JSON content:"
cat "$JSON_FILE"