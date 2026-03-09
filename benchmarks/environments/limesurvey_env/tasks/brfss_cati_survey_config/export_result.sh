#!/bin/bash
echo "=== Exporting BRFSS CATI Survey Result ==="

source /workspace/scripts/task_utils.sh

# Fallback query function
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Identify the survey created by the agent
# Look for BRFSS or Health Interview in title, pick the most recently created
SURVEY_SID=$(limesurvey_query "
    SELECT s.sid 
    FROM lime_surveys s 
    JOIN lime_surveys_languagesettings ls ON s.sid = ls.surveyls_survey_id 
    WHERE LOWER(ls.surveyls_title) LIKE '%brfss%' 
       OR LOWER(ls.surveyls_title) LIKE '%health interview%' 
    ORDER BY s.datecreated DESC 
    LIMIT 1")

echo "Found Survey SID: $SURVEY_SID"

if [ -z "$SURVEY_SID" ]; then
    echo "No matching survey found."
    # Create empty result to avoid verifier crash
    cat > /tmp/task_result.json << EOF
{
    "survey_found": false,
    "error": "No survey with expected title found"
}
EOF
    exit 0
fi

# Fetch Survey Settings (Presentation & Navigation)
# format: G=Group, S=Question, A=All
# allowprev: Y/N
# showprogress: Y/N
# datestamp: Y/N
SETTINGS_JSON=$(limesurvey_query "
    SELECT JSON_OBJECT(
        'sid', sid,
        'format', format,
        'allowprev', allowprev,
        'showprogress', showprogress,
        'datestamp', datestamp,
        'active', active
    )
    FROM lime_surveys 
    WHERE sid = $SURVEY_SID")

# Fetch Text Elements (Title, Welcome, End)
# Using JSON_OBJECT to handle potential special characters/newlines safely
TEXT_JSON=$(limesurvey_query "
    SELECT JSON_OBJECT(
        'title', surveyls_title,
        'welcome', surveyls_welcometext,
        'end', surveyls_endtext
    )
    FROM lime_surveys_languagesettings
    WHERE surveyls_survey_id = $SURVEY_SID
    LIMIT 1")

# Fetch Group Count
GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid = $SURVEY_SID")

# Fetch Question Count (excluding subquestions)
QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid = $SURVEY_SID AND parent_qid = 0")

# Construct final JSON
# We use python to safely merge the JSON parts to avoid shell quoting hell
python3 -c "
import json
import sys

try:
    settings = json.loads('''$SETTINGS_JSON''')
    text = json.loads('''$TEXT_JSON''')
    
    result = {
        'survey_found': True,
        'settings': settings,
        'text': text,
        'counts': {
            'groups': int('$GROUP_COUNT'),
            'questions': int('$QUESTION_COUNT')
        },
        'timestamp': '$(date +%s)'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
    print('Result exported successfully.')
except Exception as e:
    print(f'Error constructing JSON: {e}')
    # Fallback error JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'survey_found': True, 'error': str(e)}, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json