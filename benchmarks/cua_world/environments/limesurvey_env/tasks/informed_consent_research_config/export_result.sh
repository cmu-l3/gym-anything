#!/bin/bash
echo "=== Exporting Informed Consent Research Result ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Find the target survey
# We look for the most recently created survey that matches the title keywords
echo "Searching for survey..."
SURVEY_QUERY="SELECT s.sid, sl.surveyls_title, sl.surveyls_description, sl.surveyls_welcometext, sl.surveyls_endtext, sl.surveyls_url, s.active, s.anonymized, s.format, s.showprogress, s.allowprev 
FROM lime_surveys s 
JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
WHERE LOWER(sl.surveyls_title) LIKE '%social media%' 
ORDER BY s.datecreated DESC LIMIT 1"

SURVEY_DATA=$(limesurvey_query "$SURVEY_QUERY")

FOUND="false"
SID=""
TITLE=""
DESCRIPTION=""
WELCOME=""
ENDTEXT=""
URL=""
ACTIVE=""
ANONYMIZED=""
FORMAT=""
SHOWPROGRESS=""
ALLOWPREV=""

if [ -n "$SURVEY_DATA" ]; then
    FOUND="true"
    # Parse tab-separated output
    SID=$(echo "$SURVEY_DATA" | cut -f1)
    TITLE=$(echo "$SURVEY_DATA" | cut -f2)
    DESCRIPTION=$(echo "$SURVEY_DATA" | cut -f3)
    # Text fields might contain newlines/tabs, so we rely on the DB query structure being strictly ordered
    # Ideally, we fetch text fields separately to avoid delimiter issues if content has tabs
fi

# If found, fetch potentially large text fields separately to be safe against delimiters
if [ "$FOUND" = "true" ]; then
    WELCOME=$(limesurvey_query "SELECT surveyls_welcometext FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID")
    ENDTEXT=$(limesurvey_query "SELECT surveyls_endtext FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID")
    URL=$(limesurvey_query "SELECT surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID")
    
    # Get settings
    SETTINGS=$(limesurvey_query "SELECT active, anonymized, format, showprogress, allowprev FROM lime_surveys WHERE sid=$SID")
    ACTIVE=$(echo "$SETTINGS" | cut -f1)
    ANONYMIZED=$(echo "$SETTINGS" | cut -f2)
    FORMAT=$(echo "$SETTINGS" | cut -f3)
    SHOWPROGRESS=$(echo "$SETTINGS" | cut -f4)
    ALLOWPREV=$(echo "$SETTINGS" | cut -f5)

    echo "Found Survey SID: $SID"
else
    echo "No survey found matching title."
fi

# 2. Check Structure (Groups and Questions)
GROUP_COUNT=0
QUESTION_COUNT=0
MANDATORY_CONSENT_EXISTS="false"

if [ "$FOUND" = "true" ]; then
    GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID")
    QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0")
    
    # Check for mandatory question in the first group (Informed Consent group)
    # We find the group with the lowest group_order
    FIRST_GID=$(limesurvey_query "SELECT gid FROM lime_groups WHERE sid=$SID ORDER BY group_order ASC LIMIT 1")
    
    if [ -n "$FIRST_GID" ]; then
        # Check if there is a mandatory question in this group
        MAND_CHECK=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND gid=$FIRST_GID AND mandatory='Y' AND parent_qid=0")
        if [ "$MAND_CHECK" -ge 1 ]; then
            MANDATORY_CONSENT_EXISTS="true"
        fi
    fi
fi

# 3. Create JSON payload
# Use python to construct JSON to handle escaping of large text blocks correctly
python3 -c "
import json
import sys

data = {
    'found': '$FOUND' == 'true',
    'sid': '$SID',
    'title': '''$TITLE''',
    'description': '''$DESCRIPTION''',
    'welcome_text': '''$WELCOME''',
    'end_text': '''$ENDTEXT''',
    'url': '$URL',
    'active': '$ACTIVE',
    'anonymized': '$ANONYMIZED',
    'format': '$FORMAT',
    'showprogress': '$SHOWPROGRESS',
    'allowprev': '$ALLOWPREV',
    'group_count': int('$GROUP_COUNT') if '$GROUP_COUNT'.isdigit() else 0,
    'question_count': int('$QUESTION_COUNT') if '$QUESTION_COUNT'.isdigit() else 0,
    'mandatory_consent_exists': '$MANDATORY_CONSENT_EXISTS' == 'true',
    'task_start': $TASK_START,
    'task_end': $TASK_END
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Sanity check
echo "Result summary:"
grep -E "found|sid|active|group_count" /tmp/task_result.json || true

echo "=== Export Complete ==="