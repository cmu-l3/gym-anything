#!/bin/bash
echo "=== Exporting Bulk Mandatory Update Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# DB Query Helper
query_db() {
    limesurvey_query "$1"
}

SID="12345"

# 1. Check Mandatory Status for all target questions
# We select title and mandatory status for all top-level questions in this survey
Q_STATUS_RAW=$(query_db "SELECT title, mandatory FROM lime_questions WHERE sid=$SID AND parent_qid=0")

# 2. Check Survey Activation Status
ACTIVE_STATUS=$(query_db "SELECT active FROM lime_surveys WHERE sid=$SID")

# 3. Check Data Integrity (Check text of Q1 to ensure it wasn't deleted/recreated with wrong text)
Q1_TEXT=$(query_db "SELECT question FROM lime_question_l10ns WHERE qid=(SELECT qid FROM lime_questions WHERE sid=$SID AND title='Q1' LIMIT 1)")

# 4. Check Question Count (to ensure no deletions)
FINAL_Q_COUNT=$(query_db "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0")
INITIAL_Q_COUNT=$(cat /tmp/initial_question_count 2>/dev/null || echo "0")

# Parse Q_STATUS_RAW into JSON object string
# Output format from MySQL -N is "Title\tStatus" per line
# We'll convert this to a JSON dictionary: {"Q1": "Y", "Q2": "N", ...}
Q_JSON_PARTS=""
while IFS=$'\t' read -r title status; do
    if [ -n "$title" ]; then
        if [ -n "$Q_JSON_PARTS" ]; then Q_JSON_PARTS="$Q_JSON_PARTS, "; fi
        Q_JSON_PARTS="$Q_JSON_PARTS\"$title\": \"$status\""
    fi
done <<< "$Q_STATUS_RAW"
Q_STATUS_JSON="{ $Q_JSON_PARTS }"

# Escape Q1 text for JSON
Q1_TEXT_SAFE=$(echo "$Q1_TEXT" | sed 's/"/\\"/g' | tr -d '\n\r')

# Create result JSON
cat > /tmp/result_temp.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "survey_active": "$ACTIVE_STATUS",
    "question_statuses": $Q_STATUS_JSON,
    "q1_text": "$Q1_TEXT_SAFE",
    "initial_q_count": $INITIAL_Q_COUNT,
    "final_q_count": $FINAL_Q_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safely move result
export_json_result "$(cat /tmp/result_temp.json)" "/tmp/task_result.json"
rm -f /tmp/result_temp.json

echo "Export complete. Result:"
cat /tmp/task_result.json