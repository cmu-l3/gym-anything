#!/bin/bash
echo "=== Exporting Framing Effect Experiment Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Helper for JSON string escaping
json_escape() {
    echo "$1" | sed 's/"/\\"/g' | tr -d '\n'
}

# 1. Find the survey ID based on title
# We look for the newest survey that contains "Framing Effect"
SURVEY_QUERY="SELECT s.sid, sl.surveyls_title, s.active, s.anonymized, s.allowprev 
              FROM lime_surveys s 
              JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id 
              WHERE sl.surveyls_title LIKE '%Framing Effect%' 
              ORDER BY s.sid DESC LIMIT 1"

SURVEY_DATA=$(limesurvey_query "$SURVEY_QUERY")

SID=""
TITLE=""
ACTIVE="N"
ANONYMIZED="N"
ALLOWPREV="Y"

if [ -n "$SURVEY_DATA" ]; then
    SID=$(echo "$SURVEY_DATA" | cut -f1)
    TITLE=$(echo "$SURVEY_DATA" | cut -f2)
    ACTIVE=$(echo "$SURVEY_DATA" | cut -f3)
    ANONYMIZED=$(echo "$SURVEY_DATA" | cut -f4)
    ALLOWPREV=$(echo "$SURVEY_DATA" | cut -f5)
    echo "Found Survey: SID=$SID, Title='$TITLE'"
else
    echo "No survey found with 'Framing Effect' in title."
fi

# 2. Get Group Data
GROUP_JSON="[]"
if [ -n "$SID" ]; then
    # Get group details: gid, group_name, randomization_group
    # Note: randomization_group is empty string if not set
    GROUP_QUERY="SELECT g.gid, gl.group_name, g.randomization_group 
                 FROM lime_groups g 
                 JOIN lime_group_l10ns gl ON g.gid = gl.gid 
                 WHERE g.sid = $SID 
                 ORDER BY g.group_order ASC"
    
    # We need to construct a JSON array of objects manually or via python
    # Using python for reliable parsing of tab-separated SQL output
    GROUP_JSON=$(python3 -c "
import subprocess, json
cmd = ['docker', 'exec', 'limesurvey-db', 'mysql', '-u', 'limesurvey', '-plimesurvey_pass', 'limesurvey', '-N', '-e', \"$GROUP_QUERY\"]
try:
    out = subprocess.check_output(cmd).decode('utf-8')
    groups = []
    for line in out.strip().split('\n'):
        if not line: continue
        parts = line.split('\t')
        if len(parts) >= 3:
            groups.append({
                'gid': parts[0],
                'name': parts[1],
                'randomization_group': parts[2]
            })
        elif len(parts) == 2: # handle empty randomization group which might be missing in split if at end
             groups.append({
                'gid': parts[0],
                'name': parts[1],
                'randomization_group': ''
            })
    print(json.dumps(groups))
except Exception as e:
    print('[]')
")
fi

# 3. Count Questions
QUESTION_COUNT=0
if [ -n "$SID" ]; then
    QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=$SID AND parent_qid=0")
fi

# 4. Anti-gaming check
INITIAL_COUNT=$(cat /tmp/initial_survey_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_survey_count)

# Export to JSON
cat > /tmp/task_result_temp.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_survey_count": $INITIAL_COUNT,
    "current_survey_count": $CURRENT_COUNT,
    "survey_found": $([ -n "$SID" ] && echo "true" || echo "false"),
    "survey_id": "$SID",
    "survey_title": "$(json_escape "$TITLE")",
    "active": "$ACTIVE",
    "anonymized": "$ANONYMIZED",
    "allowprev": "$ALLOWPREV",
    "question_count": ${QUESTION_COUNT:-0},
    "groups": $GROUP_JSON
}
EOF

export_json_result "$(cat /tmp/task_result_temp.json)" "/tmp/task_result.json"
rm /tmp/task_result_temp.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="