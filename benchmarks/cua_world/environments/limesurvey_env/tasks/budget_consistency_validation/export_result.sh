#!/bin/bash
echo "=== Exporting Budget Validation Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Identify the survey and question
SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title='Household Financial Wellness 2025' LIMIT 1")
QID_EXPENSE=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='Q_EXPENSES' AND parent_qid=0")

echo "Survey ID: $SID"
echo "Expense Question ID: $QID_EXPENSE"

# 1. Check Validation Equation
# Note: LimeSurvey stores this in lime_question_attributes with attribute='em_validation_q'
VALIDATION_EQ=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID_EXPENSE AND attribute='em_validation_q'")

# 2. Check Validation Tip
# Note: Stored in lime_question_attributes with attribute='em_validation_q_tip'
# BUT: In some versions it might be in lime_question_attributes_l10ns if translated, 
# or just lime_question_attributes if language agnostic. 
# Usually 'em_validation_q_tip' is in attributes.
VALIDATION_TIP=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$QID_EXPENSE AND attribute='em_validation_q_tip'")

# Sanitize for JSON
EQ_SAFE=$(echo "$VALIDATION_EQ" | sed 's/"/\\"/g' | tr -d '\n\r')
TIP_SAFE=$(echo "$VALIDATION_TIP" | sed 's/"/\\"/g' | tr -d '\n\r')

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sid": "$SID",
    "qid_expense": "$QID_EXPENSE",
    "validation_equation": "$EQ_SAFE",
    "validation_tip": "$TIP_SAFE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="