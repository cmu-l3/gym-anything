#!/bin/bash
echo "=== Exporting Manual Data Entry Result ==="

source /workspace/scripts/task_utils.sh

# 1. Get Survey ID
SID=$(cat /tmp/task_sid.txt 2>/dev/null || echo "")

if [ -z "$SID" ]; then
    # Fallback: find by title if SID file missing
    SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title='Community Health Needs Assessment 2024' LIMIT 1")
fi

echo "Survey ID: $SID"

# 2. Check if Response Table Exists
TABLE_EXISTS=$(limesurvey_query "SHOW TABLES LIKE 'lime_survey_${SID}'")

RESPONSES_JSON="[]"
ROW_COUNT=0

if [ -n "$TABLE_EXISTS" ]; then
    # 3. Export Data using Python to handle complex SQL -> JSON mapping properly
    # We need to map column names like `123X45X6` to Question Codes `QZIP`, etc.
    
    cat > /tmp/export_responses.py << EOF
import json
import subprocess
import sys

sid = "$SID"

def db_query(sql):
    cmd = ["docker", "exec", "limesurvey-db", "mysql", "-u", "limesurvey", "-plimesurvey_pass", "limesurvey", "-N", "-e", sql]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode('utf-8').strip()
        return res
    except Exception as e:
        return ""

# Get Question Code to Column Mapping
# Schema: SID + 'X' + GID + 'X' + QID
sql_map = f"""
SELECT q.title, CONCAT('{sid}','X',q.gid,'X',q.qid) 
FROM lime_questions q 
WHERE q.sid={sid} AND q.parent_qid=0
"""
mapping_raw = db_query(sql_map)
col_map = {} # QCODE -> Column Name
if mapping_raw:
    for line in mapping_raw.split('\n'):
        parts = line.split('\t')
        if len(parts) >= 2:
            col_map[parts[0]] = parts[1]

# Construct Select Query
# We want: id, submitdate, QZIP, QHEALTH, QDAYS, QINSURED, QAGE
cols_to_fetch = ["id", "submitdate"]
aliases = ["id", "submitdate"]

questions = ["QZIP", "QHEALTH", "QDAYS", "QINSURED", "QAGE"]
valid_questions = []

for q in questions:
    if q in col_map:
        cols_to_fetch.append(col_map[q])
        aliases.append(q)
        valid_questions.append(q)

if not valid_questions:
    print("[]")
    sys.exit(0)

cols_str = ", ".join(cols_to_fetch)
sql_data = f"SELECT {cols_str} FROM lime_survey_{sid} ORDER BY id ASC"

data_raw = db_query(sql_data)
results = []

if data_raw:
    for line in data_raw.split('\n'):
        parts = line.split('\t')
        row = {}
        # Handle potential empty fields or mismatches
        for i, alias in enumerate(aliases):
            val = parts[i] if i < len(parts) else ""
            # Handle NULLs
            if val == "NULL": val = None
            row[alias] = val
        results.append(row)

print(json.dumps(results))
EOF

    RESPONSES_JSON=$(python3 /tmp/export_responses.py)
    ROW_COUNT=$(echo "$RESPONSES_JSON" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
else
    echo "Response table for SID $SID not found."
fi

# 4. Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "survey_id": "$SID",
    "table_exists": "$( [ -n "$TABLE_EXISTS" ] && echo "true" || echo "false" )",
    "response_count": $ROW_COUNT,
    "responses": $RESPONSES_JSON,
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="