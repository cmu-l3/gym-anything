#!/bin/bash
echo "=== Exporting Team User Permissions Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ==============================================================================
# DATA EXTRACTION
# We need to query multiple tables: surveys, users, permissions, questions
# ==============================================================================

# 1. FIND THE SURVEY
# Look for title matching "Consumer Brand Perception"
SURVEY_QUERY="SELECT s.sid, ls.surveyls_title, s.datecreated 
              FROM lime_surveys s 
              JOIN lime_surveys_languagesettings ls ON s.sid = ls.surveyls_survey_id 
              WHERE ls.surveyls_title LIKE '%Consumer Brand Perception%' 
              ORDER BY s.datecreated DESC LIMIT 1"

SURVEY_DATA=$(limesurvey_query "$SURVEY_QUERY" 2>/dev/null || echo "")

SID=""
SURVEY_TITLE=""
SURVEY_CREATED=""
SURVEY_FOUND="false"
GROUP_COUNT="0"
QUESTION_COUNT="0"

if [ -n "$SURVEY_DATA" ]; then
    SURVEY_FOUND="true"
    SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    # Extract title (handling spaces)
    SURVEY_TITLE=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID" 2>/dev/null)
    SURVEY_CREATED=$(echo "$SURVEY_DATA" | awk '{print $NF}') # Last column is date
    
    # Check structure
    GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID" 2>/dev/null || echo "0")
    QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0" 2>/dev/null || echo "0")
    
    echo "Found Survey: $SID ($SURVEY_TITLE)"
else
    echo "Survey not found."
fi

# 2. FIND THE USERS
# We look for j.martinez and r.nakamura
USER_JM_DATA=$(limesurvey_query "SELECT uid, created FROM lime_users WHERE users_name='j.martinez'" 2>/dev/null || echo "")
USER_RN_DATA=$(limesurvey_query "SELECT uid, created FROM lime_users WHERE users_name='r.nakamura'" 2>/dev/null || echo "")

JM_UID=""
RN_UID=""
JM_CREATED=""
RN_CREATED=""
JM_FOUND="false"
RN_FOUND="false"

if [ -n "$USER_JM_DATA" ]; then
    JM_FOUND="true"
    JM_UID=$(echo "$USER_JM_DATA" | awk '{print $1}')
    JM_CREATED=$(echo "$USER_JM_DATA" | awk '{print $2}')
fi

if [ -n "$USER_RN_DATA" ]; then
    RN_FOUND="true"
    RN_UID=$(echo "$USER_RN_DATA" | awk '{print $1}')
    RN_CREATED=$(echo "$USER_RN_DATA" | awk '{print $2}')
fi

# 3. CHECK PERMISSIONS
# We need to check if these users have 'responses' permission with read_p=1 for this specific SID
# entity='survey', entity_id=SID
JM_PERM_READ="0"
RN_PERM_READ="0"

if [ "$SURVEY_FOUND" = "true" ]; then
    if [ "$JM_FOUND" = "true" ]; then
        # Check permissions for Julia
        PERM_ROW=$(limesurvey_query "SELECT read_p FROM lime_permissions WHERE entity='survey' AND entity_id=$SID AND uid=$JM_UID AND permission='responses'" 2>/dev/null || echo "")
        if [ "$PERM_ROW" == "1" ]; then JM_PERM_READ="1"; fi
        
        # Check if they accidentally have global permission (entity=global) - usually not requested but good to know
        # Note: Task specifically requests permissions for the survey.
    fi

    if [ "$RN_FOUND" = "true" ]; then
        # Check permissions for Ryo
        PERM_ROW=$(limesurvey_query "SELECT read_p FROM lime_permissions WHERE entity='survey' AND entity_id=$SID AND uid=$RN_UID AND permission='responses'" 2>/dev/null || echo "")
        if [ "$PERM_ROW" == "1" ]; then RN_PERM_READ="1"; fi
    fi
fi

# 4. CONSTRUCT JSON
# Using python to create safe JSON
python3 << PYEOF
import json
import time

data = {
    "task_start_ts": $TASK_START,
    "survey": {
        "found": $SURVEY_FOUND,
        "sid": "$SID",
        "title": """$SURVEY_TITLE""",
        "created_date": "$SURVEY_CREATED",
        "group_count": int("$GROUP_COUNT"),
        "question_count": int("$QUESTION_COUNT")
    },
    "users": {
        "j_martinez": {
            "found": $JM_FOUND,
            "uid": "$JM_UID",
            "created_date": "$JM_CREATED",
            "perm_response_read": $JM_PERM_READ
        },
        "r_nakamura": {
            "found": $RN_FOUND,
            "uid": "$RN_UID",
            "created_date": "$RN_CREATED",
            "perm_response_read": $RN_PERM_READ
        }
    },
    "timestamp": time.time()
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=4)
PYEOF

# Clean up permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="