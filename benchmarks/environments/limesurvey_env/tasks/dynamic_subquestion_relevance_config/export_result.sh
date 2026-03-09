#!/bin/bash
echo "=== Exporting Dynamic Subquestion Relevance Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Find the Survey ID
SURVEY_ID=$(get_survey_id "New Hire IT Provisioning 2025")

FOUND="false"
SURVEY_ACTIVE="N"
DEPT_QID=""
TOOLS_QID=""
DEPT_ANSWERS=""
TOOLS_SUBQUESTIONS=""

if [ -n "$SURVEY_ID" ]; then
    FOUND="true"
    echo "Found Survey ID: $SURVEY_ID"
    
    # Check if active
    SURVEY_ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SURVEY_ID" 2>/dev/null || echo "N")
    
    # 2. Get Question IDs for DEPT and TOOLS
    DEPT_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SURVEY_ID AND title='DEPT' AND parent_qid=0" 2>/dev/null || echo "")
    TOOLS_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SURVEY_ID AND title='TOOLS' AND parent_qid=0" 2>/dev/null || echo "")
    
    # 3. Get Answer Options for DEPT (Code and Text)
    # We need to verify they used SALES, ENG, LEGAL codes
    if [ -n "$DEPT_QID" ]; then
        # Format: code:answer|code:answer...
        DEPT_ANSWERS=$(limesurvey_query "SELECT CONCAT(a.code, ':', al.answer) FROM lime_answers a JOIN lime_answer_l10ns al ON a.qid=al.qid WHERE a.qid=$DEPT_QID" 2>/dev/null | tr '\n' '|')
    fi

    # 4. Get Subquestions and Relevance Logic for TOOLS
    # Subquestions in Multiple Choice are stored in lime_questions with parent_qid = TOOLS_QID
    # We select title (subquestion code) and relevance (the logic equation)
    if [ -n "$TOOLS_QID" ]; then
        # Format: code:relevance|code:relevance...
        # Using a specialized query to handle potential NULL relevance (though usually default is 1)
        TOOLS_SUBQUESTIONS=$(limesurvey_query "SELECT CONCAT(title, '||', IFNULL(relevance, '1')) FROM lime_questions WHERE parent_qid=$TOOLS_QID" 2>/dev/null | tr '\n' ';')
    fi
else
    echo "Survey not found."
fi

# Sanitize strings for JSON inclusion (escape quotes)
DEPT_ANSWERS_SAFE=$(echo "$DEPT_ANSWERS" | sed 's/"/\\"/g')
TOOLS_SUBQUESTIONS_SAFE=$(echo "$TOOLS_SUBQUESTIONS" | sed 's/"/\\"/g')

# Create JSON result
# We use a temp file pattern to avoid permissions issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "survey_found": $FOUND,
    "survey_id": "$SURVEY_ID",
    "survey_active": "$SURVEY_ACTIVE",
    "dept_qid": "$DEPT_QID",
    "tools_qid": "$TOOLS_QID",
    "dept_answers_raw": "$DEPT_ANSWERS_SAFE",
    "tools_logic_raw": "$TOOLS_SUBQUESTIONS_SAFE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Exported Data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="