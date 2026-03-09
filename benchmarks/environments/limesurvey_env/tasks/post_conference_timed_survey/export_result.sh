#!/bin/bash
echo "=== Exporting Post-Conference Survey Result ==="

source /workspace/scripts/task_utils.sh

# Helper for SQL
db_query() {
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
}

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Identify the target survey
# We look for the most recently created survey that matches the title keyword
echo "Searching for survey..."
SURVEY_SID=$(db_query "
    SELECT s.sid 
    FROM lime_surveys s 
    JOIN lime_surveys_languagesettings ls ON s.sid = ls.surveyls_survey_id 
    WHERE ls.surveyls_title LIKE '%Data Science Summit%' 
    ORDER BY s.datecreated DESC 
    LIMIT 1
")

FOUND="false"
TITLE=""
START_DATE=""
EXPIRES_DATE=""
SHOW_PROGRESS=""
ALLOW_PREV=""
WELCOME_TEXT=""
END_URL=""
GROUP_COUNT=0
RANKING_Q_EXISTS="false"
ANSWER_OPTION_COUNT=0

if [ -n "$SURVEY_SID" ]; then
    FOUND="true"
    echo "Found Survey ID: $SURVEY_SID"

    # 2. Get Survey Settings
    # startdate, expires, showprogress, allowprev
    SETTINGS=$(db_query "SELECT startdate, expires, showprogress, allowprev FROM lime_surveys WHERE sid=$SURVEY_SID")
    START_DATE=$(echo "$SETTINGS" | cut -f1)
    EXPIRES_DATE=$(echo "$SETTINGS" | cut -f2)
    SHOW_PROGRESS=$(echo "$SETTINGS" | cut -f3)
    ALLOW_PREV=$(echo "$SETTINGS" | cut -f4)

    # 3. Get Language Settings (Text)
    # welcometext, endtext, url
    LANG_SETTINGS=$(db_query "SELECT surveyls_title, surveyls_welcometext, surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SURVEY_SID LIMIT 1")
    # Handle potentially multi-line text fields safely? MySQL -N outputs tab separated.
    # We might need to be careful with newlines in welcome text. 
    # For robust export, let's fetch individual fields or use Python.
    
    TITLE=$(db_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SURVEY_SID LIMIT 1")
    WELCOME_TEXT=$(db_query "SELECT surveyls_welcometext FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SURVEY_SID LIMIT 1")
    END_URL=$(db_query "SELECT surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SURVEY_SID LIMIT 1")

    # 4. Check Structure
    GROUP_COUNT=$(db_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SURVEY_SID")
    
    # Check for Ranking Question (Type 'R')
    RANKING_QID=$(db_query "SELECT qid FROM lime_questions WHERE sid=$SURVEY_SID AND type='R' LIMIT 1")
    
    if [ -n "$RANKING_QID" ]; then
        RANKING_Q_EXISTS="true"
        # Count answer options for this question
        ANSWER_OPTION_COUNT=$(db_query "SELECT COUNT(*) FROM lime_answers WHERE qid=$RANKING_QID")
    fi

else
    echo "No matching survey found."
fi

# Create JSON Result safely
# We use Python to construct JSON to handle potential special characters in user text
python3 -c "
import json
import sys

data = {
    'found': '$FOUND' == 'true',
    'sid': '$SURVEY_SID',
    'title': '''$TITLE''',
    'start_date': '$START_DATE',
    'expires_date': '$EXPIRES_DATE',
    'show_progress': '$SHOW_PROGRESS',
    'allow_prev': '$ALLOW_PREV',
    'welcome_text': '''$WELCOME_TEXT''',
    'end_url': '$END_URL',
    'group_count': int('$GROUP_COUNT') if '$GROUP_COUNT'.isdigit() else 0,
    'ranking_question_exists': '$RANKING_Q_EXISTS' == 'true',
    'answer_option_count': int('$ANSWER_OPTION_COUNT') if '$ANSWER_OPTION_COUNT'.isdigit() else 0,
    'task_start_time': $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="