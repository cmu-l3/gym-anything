#!/bin/bash
echo "=== Exporting generate_inventory_report results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state screenshot
take_screenshot /tmp/final_screenshot.png

# Paths and timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/seb_inventory_report.json"
REPORT_EXISTS="false"
CREATED_AFTER_START="false"

# Check if the agent created the report file
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        CREATED_AFTER_START="true"
    fi
    # Copy the report to a temp location for the verifier to safely pull
    cp "$REPORT_PATH" /tmp/agent_report.json
    chmod 666 /tmp/agent_report.json 2>/dev/null || true
fi

# =============================================================================
# EXTRACT GROUND TRUTH DIRECTLY FROM DATABASE
# =============================================================================
# We extract this into a JSON file so the host verifier can validate the agent's
# report against the actual live data without needing exec_in_env capabilities.

python3 << 'PYEOF'
import json
import subprocess

def db_query(query):
    res = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root', '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True
    )
    return res.stdout.strip()

def get_rows(query):
    raw = db_query(query)
    if not raw: return []
    return [line.split('\t') for line in raw.split('\n') if line.strip()]

gt = {}

# 1. Institutions
gt['institutions'] = []
for r in get_rows("SELECT id, name, active FROM institution"):
    gt['institutions'].append({'id': str(r[0]), 'name': str(r[1]), 'active': r[2]})

# 2. Users
user_query = """SELECT username, name, email, 
CASE role WHEN 0 THEN 'SEB_SERVER_ADMIN' WHEN 1 THEN 'INSTITUTIONAL_ADMIN' WHEN 2 THEN 'EXAM_ADMIN' WHEN 4 THEN 'EXAM_SUPPORTER' ELSE CAST(role AS CHAR) END,
institution_id, active FROM user"""
gt['users'] = []
for r in get_rows(user_query):
    gt['users'].append({
        'username': str(r[0]), 
        'name': str(r[1]), 
        'email': str(r[2]), 
        'role': str(r[3]), 
        'institution_id': str(r[4]) if len(r)>4 else '', 
        'active': r[5] if len(r)>5 else '0'
    })

# 3. Exam Configurations
gt['configs'] = []
for r in get_rows("SELECT id, name, status, institution_id FROM configuration_node"):
    gt['configs'].append({
        'id': str(r[0]), 
        'name': str(r[1]), 
        'status': str(r[2]), 
        'institution_id': str(r[3]) if len(r)>3 else ''
    })

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(gt, f)
PYEOF

chmod 666 /tmp/ground_truth.json 2>/dev/null || true

# =============================================================================
# SAVE METADATA
# =============================================================================
cat > /tmp/task_result.json << EOF
{
    "report_exists": $REPORT_EXISTS,
    "created_after_start": $CREATED_AFTER_START
}
EOF
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="