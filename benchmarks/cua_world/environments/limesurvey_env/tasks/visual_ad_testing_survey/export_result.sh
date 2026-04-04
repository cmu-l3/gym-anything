#!/bin/bash
echo "=== Exporting Visual Ad Testing Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Find the Survey
echo "Searching for survey..."
SURVEY_DATA=$(limesurvey_query "SELECT sid, surveyls_title, active FROM lime_surveys_languagesettings JOIN lime_surveys ON sid=surveyls_survey_id WHERE LOWER(surveyls_title) LIKE '%beverage%packaging%' LIMIT 1")

SID=""
TITLE=""
ACTIVE="N"
QUESTIONS_JSON="[]"
UPLOADED_FILES="[]"

if [ -n "$SURVEY_DATA" ]; then
    SID=$(echo "$SURVEY_DATA" | awk '{print $1}')
    TITLE=$(echo "$SURVEY_DATA" | awk '{$1=""; $NF=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
    ACTIVE=$(echo "$SURVEY_DATA" | awk '{print $NF}')
    
    echo "Found Survey SID: $SID"

    # 2. Get Questions (Code, Text, Type)
    # Using python to format JSON directly from query output to handle special chars safely
    QUESTIONS_JSON=$(python3 -c "
import subprocess, json
cmd = [
    'docker', 'exec', 'limesurvey-db', 'mysql', '-u', 'limesurvey', '-plimesurvey_pass', 'limesurvey', '-N', '-e',
    'SELECT q.title, q.type, ql.question FROM lime_questions q JOIN lime_question_l10ns ql ON q.qid=ql.qid WHERE q.sid=$SID AND q.parent_qid=0'
]
try:
    out = subprocess.check_output(cmd).decode('utf-8', errors='ignore')
    qs = []
    for line in out.strip().split('\n'):
        if not line: continue
        parts = line.split('\t')
        if len(parts) >= 3:
            qs.append({'code': parts[0], 'type': parts[1], 'text': parts[2]})
    print(json.dumps(qs))
except Exception as e:
    print('[]')
")

    # 3. Check Uploaded Files in the LimeSurvey Container
    # Files are stored in /var/www/html/upload/surveys/{SID}/images/
    echo "Checking uploaded files for SID $SID..."
    
    # We use docker exec to list files inside the container
    UPLOADED_FILES=$(docker exec limesurvey-app sh -c "ls -1 /var/www/html/upload/surveys/$SID/images/ 2>/dev/null || echo ''" | python3 -c "
import sys, json
files = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(files))
")

else
    echo "Survey not found."
fi

# Sanitize title for JSON
SAFE_TITLE=$(echo "$TITLE" | sed 's/"/\\"/g')

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "survey_found": $(if [ -n "$SID" ]; then echo "true"; else echo "false"; fi),
    "sid": "$SID",
    "title": "$SAFE_TITLE",
    "active": "$ACTIVE",
    "questions": $QUESTIONS_JSON,
    "uploaded_files": $UPLOADED_FILES,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="