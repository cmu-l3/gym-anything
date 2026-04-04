#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Fallback
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SID=$(cat /tmp/task_sid 2>/dev/null || echo "")

take_screenshot /tmp/task_final.png

# 1. Check if Survey is Active
IS_ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=${SID}" 2>/dev/null || echo "N")

# 2. Check for New Question 'dept'
HAS_QUESTION=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=${SID} AND title='dept'" 2>/dev/null || echo "0")
QUESTION_TEXT=$(limesurvey_query "SELECT question FROM lime_question_l10ns WHERE qid=(SELECT qid FROM lime_questions WHERE sid=${SID} AND title='dept' LIMIT 1)" 2>/dev/null || echo "")
QUESTION_OPTIONS=$(limesurvey_query "SELECT COUNT(*) FROM lime_answers WHERE qid=(SELECT qid FROM lime_questions WHERE sid=${SID} AND title='dept' LIMIT 1)" 2>/dev/null || echo "0")

# 3. Check Response Data
RESPONSE_COUNT="0"
VERBATIM_FOUND="false"
TIMESTAMPS_PRESERVED="false"
OLDEST_DATE=""

if [ "$IS_ACTIVE" == "Y" ]; then
    RESPONSE_TABLE="lime_survey_${SID}"
    
    # Count rows
    RESPONSE_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM ${RESPONSE_TABLE}" 2>/dev/null || echo "0")
    
    # Check specific verbatim to ensure it's the original data
    VERBATIM_CHECK=$(limesurvey_query "SELECT COUNT(*) FROM ${RESPONSE_TABLE} WHERE comments LIKE '%flexible hours are the best part%'" 2>/dev/null || echo "0")
    if [ "$VERBATIM_CHECK" -gt "0" ]; then
        VERBATIM_FOUND="true"
    fi

    # Check timestamps
    # If data was restored, the submitdate should be OLDER than TASK_START
    # If data was manually re-entered, submitdate would be NEWER than TASK_START
    OLDEST_DATE=$(limesurvey_query "SELECT MIN(submitdate) FROM ${RESPONSE_TABLE}" 2>/dev/null)
    
    # Convert SQL date to epoch for comparison
    if [ -n "$OLDEST_DATE" ] && [ "$OLDEST_DATE" != "NULL" ]; then
        OLDEST_EPOCH=$(date -d "$OLDEST_DATE" +%s 2>/dev/null || echo "0")
        if [ "$OLDEST_EPOCH" -lt "$TASK_START" ] && [ "$OLDEST_EPOCH" -gt 0 ]; then
            TIMESTAMPS_PRESERVED="true"
        fi
    fi
fi

# 4. Check if Archive Table Exists (Evidence of Deactivation)
# Look for table starting with lime_old_survey_{SID}_
ARCHIVE_EXISTS="false"
ARCHIVE_TABLE=$(limesurvey_query "SHOW TABLES LIKE 'lime_old_survey_${SID}_%'" 2>/dev/null | head -n 1)
if [ -n "$ARCHIVE_TABLE" ]; then
    ARCHIVE_EXISTS="true"
fi

# Create JSON
JSON_PATH="/tmp/task_result.json"
cat > "$JSON_PATH" << EOF
{
    "sid": "$SID",
    "is_active": "$IS_ACTIVE",
    "has_question": $HAS_QUESTION,
    "question_text": "$QUESTION_TEXT",
    "question_options_count": $QUESTION_OPTIONS,
    "response_count": $RESPONSE_COUNT,
    "verbatim_found": $VERBATIM_FOUND,
    "timestamps_preserved": $TIMESTAMPS_PRESERVED,
    "oldest_response_date": "$OLDEST_DATE",
    "archive_table_exists": $ARCHIVE_EXISTS,
    "task_start_time": $TASK_START
}
EOF

# Permission fix
chmod 666 "$JSON_PATH" 2>/dev/null || sudo chmod 666 "$JSON_PATH"

echo "=== Export Complete ==="
cat "$JSON_PATH"