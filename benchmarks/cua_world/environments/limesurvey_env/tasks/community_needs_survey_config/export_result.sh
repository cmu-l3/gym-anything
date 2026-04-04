#!/bin/bash
echo "=== Exporting Community Needs Survey Config Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definition
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get Task Start Time
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Find the survey ID based on title (case insensitive)
# We look for the MOST RECENT one matching the title
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%riverside%community%needs%' ORDER BY s.datecreated DESC LIMIT 1" 2>/dev/null || echo "")

SURVEY_FOUND="false"
SURVEY_DATA="{}"

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey SID: $SID"

    # Fetch Survey Settings from lime_surveys
    # Columns: active, format, showprogress, allowprev, datestamp, ipaddr, refurl, adminemail
    # Note: admin email might be in 'adminemail' OR 'emailnotificationto' OR 'emailresponseto'
    SETTINGS=$(limesurvey_query "SELECT active, format, showprogress, allowprev, datestamp, ipaddr, refurl, adminemail, emailnotificationto, emailresponseto, datecreated FROM lime_surveys WHERE sid=$SID")
    
    # Parse space-separated values (assuming simple one-word values for flags, emails might be complex but we handle them)
    # Using python to parse safely to JSON to avoid bash string parsing hell
    
    PYTHON_PARSER=$(cat <<PyEOF
import sys
import json

try:
    sid = "$SID"
    # Settings line: active format showprogress allowprev datestamp ipaddr refurl adminemail notifto respto datecreated
    # Note: MySQL -N output is tab separated usually
    raw_settings = "$SETTINGS"
    parts = raw_settings.split('\t')
    
    data = {
        "sid": sid,
        "active": parts[0] if len(parts) > 0 else "N",
        "format": parts[1] if len(parts) > 1 else "",
        "showprogress": parts[2] if len(parts) > 2 else "N",
        "allowprev": parts[3] if len(parts) > 3 else "N",
        "datestamp": parts[4] if len(parts) > 4 else "N",
        "ipaddr": parts[5] if len(parts) > 5 else "Y",
        "refurl": parts[6] if len(parts) > 6 else "N",
        "adminemail": parts[7] if len(parts) > 7 else "",
        "emailnotificationto": parts[8] if len(parts) > 8 else "",
        "emailresponseto": parts[9] if len(parts) > 9 else "",
        "datecreated": parts[10] if len(parts) > 10 else "0000-00-00"
    }
    print(json.dumps(data))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PyEOF
)
    SURVEY_CONFIG=$(python3 -c "$PYTHON_PARSER")

    # Fetch Language Settings (Title, Welcome, End, URL)
    # Be careful with potential newlines in text fields
    
    # We use a specialized query to dump just the text fields to a temp file, then read with python
    # to handle escaping correctly.
    limesurvey_query "SELECT surveyls_title, surveyls_welcometext, surveyls_endtext, surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID" > /tmp/survey_text_raw.txt
    
    TEXT_PARSER=$(cat <<PyEOF
import json
import sys

try:
    with open('/tmp/survey_text_raw.txt', 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read().strip()
    
    # MySQL -N output with multiple fields is tab separated
    parts = content.split('\t')
    
    data = {
        "title": parts[0] if len(parts) > 0 else "",
        "welcome": parts[1] if len(parts) > 1 else "",
        "endtext": parts[2] if len(parts) > 2 else "",
        "url": parts[3] if len(parts) > 3 else ""
    }
    print(json.dumps(data))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PyEOF
)
    TEXT_CONFIG=$(python3 -c "$TEXT_PARSER")
    
    # Count Groups
    GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID")
    
    # Count Questions (Total)
    QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0")
    
    # Check "At least 1 question per group"
    # We count groups that have > 0 questions
    GROUPS_WITH_QUESTIONS=$(limesurvey_query "SELECT COUNT(DISTINCT g.gid) FROM lime_groups g JOIN lime_questions q ON g.gid = q.gid WHERE g.sid=$SID AND q.parent_qid=0")
    
    # Create creation timestamp check
    # Check if creation date is > task start time (approximate check, just to ensure it's new)
    # Note: datecreated is usually YYYY-MM-DD or YYYY-MM-DD HH:MM:SS.
    
    SURVEY_DATA=$(cat <<EOF
{
    "config": $SURVEY_CONFIG,
    "text": $TEXT_CONFIG,
    "stats": {
        "group_count": ${GROUP_COUNT:-0},
        "question_count": ${QUESTION_COUNT:-0},
        "groups_with_questions": ${GROUPS_WITH_QUESTIONS:-0}
    },
    "task_start_time": $TASK_START_TIME
}
EOF
)

else
    echo "Survey not found."
fi

# Assemble Final JSON
cat > /tmp/task_result.json <<EOF
{
    "survey_found": $SURVEY_FOUND,
    "survey_data": $SURVEY_DATA,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="