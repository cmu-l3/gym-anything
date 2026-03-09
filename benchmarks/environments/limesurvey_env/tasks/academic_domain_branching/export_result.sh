#!/bin/bash
echo "=== Exporting Academic Domain Branching Result ==="

source /workspace/scripts/task_utils.sh

# Define helper if not present
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find the survey ID
SURVEY_ID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%National Research Collaboration Study 2025%' LIMIT 1" 2>/dev/null)

SURVEY_FOUND="false"
GROUPS_JSON="[]"
QUESTIONS_JSON="[]"

if [ -n "$SURVEY_ID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey ID: $SURVEY_ID"

    # Export Groups (including relevance equations)
    # Using python to format as JSON safely
    GROUPS_JSON=$(python3 -c "
import subprocess, json
cmd = [\"docker\", \"exec\", \"limesurvey-db\", \"mysql\", \"-u\", \"limesurvey\", \"-plimesurvey_pass\", \"limesurvey\", \"-N\", \"-e\", \"SELECT group_name, grelevance FROM lime_groups WHERE sid=$SURVEY_ID\"]
try:
    output = subprocess.check_output(cmd).decode('utf-8')
    groups = []
    for line in output.strip().split('\n'):
        if '\t' in line:
            parts = line.split('\t')
            groups.append({'name': parts[0], 'relevance': parts[1] if len(parts) > 1 else ''})
    print(json.dumps(groups))
except:
    print('[]')
")

    # Export Questions (including validation/preg)
    QUESTIONS_JSON=$(python3 -c "
import subprocess, json
cmd = [\"docker\", \"exec\", \"limesurvey-db\", \"mysql\", \"-u\", \"limesurvey\", \"-plimesurvey_pass\", \"limesurvey\", \"-N\", \"-e\", \"SELECT title, type, preg, question FROM lime_questions q JOIN lime_question_l10ns l ON q.qid=l.qid WHERE q.sid=$SURVEY_ID AND q.parent_qid=0\"]
try:
    output = subprocess.check_output(cmd).decode('utf-8')
    questions = []
    for line in output.strip().split('\n'):
        if '\t' in line:
            parts = line.split('\t')
            questions.append({
                'code': parts[0], 
                'type': parts[1], 
                'preg': parts[2] if len(parts) > 2 else '',
                'text': parts[3] if len(parts) > 3 else ''
            })
    print(json.dumps(questions))
except:
    print('[]')
")

fi

# Get timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "survey_found": $SURVEY_FOUND,
    "survey_id": "$SURVEY_ID",
    "groups": $GROUPS_JSON,
    "questions": $QUESTIONS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="