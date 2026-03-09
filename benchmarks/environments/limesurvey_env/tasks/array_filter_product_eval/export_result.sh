#!/bin/bash
echo "=== Exporting Array Filter Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find the survey SID based on title
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid=sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%Streaming%' AND sl.surveyls_title LIKE '%Evaluation%' LIMIT 1" 2>/dev/null)

SURVEY_FOUND="false"
SURVEY_INFO="{}"
GROUPS="[]"
QUESTIONS="[]"
ATTRIBUTES="[]"

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"
    echo "Found Survey SID: $SID"

    # Get Survey Info (Active, Anonymized)
    # Using python to format as JSON safely
    SURVEY_INFO=$(python3 -c "
import subprocess, json
def q(sql):
    try:
        cmd = ['docker', 'exec', 'limesurvey-db', 'mysql', '-u', 'limesurvey', '-plimesurvey_pass', 'limesurvey', '-N', '-e', sql]
        return subprocess.check_output(cmd).decode('utf-8').strip().split('\t')
    except:
        return []

res = q(\"SELECT active, anonymized FROM lime_surveys WHERE sid=$SID\")
info = {'active': 'N', 'anonymized': 'N'}
if res and len(res) >= 2:
    info['active'] = res[0]
    info['anonymized'] = res[1]
print(json.dumps(info))
")

    # Get Groups Count
    GROUP_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_groups WHERE sid=$SID" 2>/dev/null)

    # Get Questions: QID, Title (Code), Type, ParentQID, GroupID
    # We construct a JSON list of questions
    QUESTIONS=$(python3 -c "
import subprocess, json
sid = '$SID'
cmd = ['docker', 'exec', 'limesurvey-db', 'mysql', '-u', 'limesurvey', '-plimesurvey_pass', 'limesurvey', '-N', '-e', 
       f\"SELECT qid, title, type, parent_qid, gid FROM lime_questions WHERE sid={sid}\"]
try:
    output = subprocess.check_output(cmd).decode('utf-8').strip()
    questions = []
    if output:
        for line in output.split('\n'):
            parts = line.split('\t')
            if len(parts) >= 5:
                questions.append({
                    'qid': parts[0],
                    'code': parts[1],
                    'type': parts[2],
                    'parent_qid': parts[3],
                    'gid': parts[4]
                })
    print(json.dumps(questions))
except Exception as e:
    print('[]')
")

    # Get Question Attributes (where array_filter is stored)
    # attribute name is usually 'array_filter' (sometimes 'array_filter_exclude', etc, but we want 'array_filter')
    ATTRIBUTES=$(python3 -c "
import subprocess, json
sid = '$SID'
cmd = ['docker', 'exec', 'limesurvey-db', 'mysql', '-u', 'limesurvey', '-plimesurvey_pass', 'limesurvey', '-N', '-e', 
       f\"SELECT qa.qid, qa.attribute, qa.value FROM lime_question_attributes qa JOIN lime_questions q ON qa.qid=q.qid WHERE q.sid={sid}\"]
try:
    output = subprocess.check_output(cmd).decode('utf-8').strip()
    attrs = []
    if output:
        for line in output.split('\n'):
            parts = line.split('\t')
            if len(parts) >= 3:
                attrs.append({
                    'qid': parts[0],
                    'attribute': parts[1],
                    'value': parts[2]
                })
    print(json.dumps(attrs))
except Exception as e:
    print('[]')
")

else
    GROUP_COUNT="0"
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "sid": "$SID",
    "survey_info": $SURVEY_INFO,
    "group_count": $GROUP_COUNT,
    "questions": $QUESTIONS,
    "attributes": $ATTRIBUTES,
    "task_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json