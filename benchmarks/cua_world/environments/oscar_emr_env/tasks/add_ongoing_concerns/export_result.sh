#!/bin/bash
echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ISSUE_COUNT=$(cat /tmp/initial_issue_count.txt 2>/dev/null || echo "0")
MARIA_DEMO=$(cat /tmp/maria_demo_no.txt 2>/dev/null)

if [ -z "$MARIA_DEMO" ]; then
    # Fallback lookup
    MARIA_DEMO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1" 2>/dev/null)
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# ============================================================
# Query Database for Verification
# ============================================================

echo "Querying issues for patient $MARIA_DEMO..."

# Fetch all issues linked to the patient
# We join casemgmt_issue (link) with issue (definition)
# We select relevant fields to verify content and status
# Note: In OSCAR, 'resolved' is a field in casemgmt_issue (char(1): '1' or '0' or null)

SQL_QUERY="SELECT 
    ci.id as link_id, 
    i.description, 
    ci.resolved, 
    ci.update_date, 
    i.type 
FROM casemgmt_issue ci 
JOIN issue i ON ci.issue_id = i.issue_id 
WHERE ci.demographic_no = '${MARIA_DEMO}';"

# Execute query and format as JSON array manually since we don't have python/jq easily available for complex formatting inside the shell
# We use a python one-liner to execute the query and dump to json to ensure safe escaping

python3 -c "
import subprocess
import json
import sys

def run_query(sql):
    cmd = ['docker', 'exec', 'oscar-db', 'mysql', '-u', 'oscar', '-poscar', 'oscar', '-N', '-e', sql]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

sql = \"$SQL_QUERY\"
raw_data = run_query(sql)

issues = []
if raw_data:
    for line in raw_data.split('\n'):
        parts = line.split('\t')
        if len(parts) >= 2:
            issue = {
                'link_id': parts[0],
                'description': parts[1],
                'resolved': parts[2] if len(parts) > 2 else '0',
                'update_date': parts[3] if len(parts) > 3 else '',
                'type': parts[4] if len(parts) > 4 else ''
            }
            issues.append(issue)

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_issue_count': int('$INITIAL_ISSUE_COUNT'),
    'patient_id': '$MARIA_DEMO',
    'issues': issues
}

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

# Check if file was created successfully
if [ -s /tmp/task_result.json ]; then
    echo "Result exported successfully."
else
    echo "ERROR: Failed to export result."
    echo "{}" > /tmp/task_result.json
fi

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="