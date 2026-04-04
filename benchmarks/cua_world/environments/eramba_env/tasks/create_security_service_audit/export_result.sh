#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Security Service Audit results ==="

# 1. Capture final state screenshot
take_screenshot /tmp/task_final_state.png

# 2. Get task start time and initial count
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_audit_count.txt 2>/dev/null || echo "0")
TARGET_SERVICE_ID=$(cat /tmp/target_service_id.txt 2>/dev/null || echo "")

# 3. Check for new audit records
# We look for the MOST RECENT audit created after task start
# We fetch details using python to handle potentially complex text/JSON formatting safely

python3 -c "
import json
import subprocess
import sys

def db_query(query):
    cmd = ['docker', 'exec', 'eramba-db', 'mysql', '-u', 'eramba', '-peramba_db_pass', 'eramba', '-N', '-e', query]
    try:
        return subprocess.check_output(cmd).decode('utf-8').strip()
    except:
        return ''

task_start = $TASK_START
initial_count = int('$INITIAL_COUNT')
target_service_id = '$TARGET_SERVICE_ID'

# Get current count
current_count_str = db_query('SELECT COUNT(*) FROM security_service_audits')
current_count = int(current_count_str) if current_count_str else 0

# Get the newest audit ID
newest_id = db_query('SELECT id FROM security_service_audits ORDER BY id DESC LIMIT 1')

audit_data = {
    'audit_found': False,
    'id': None,
    'service_id': None,
    'description': '',
    'planned_date': '',
    'start_date': '',
    'end_date': '',
    'result': '',
    'created_ts': 0
}

if newest_id:
    # Get creation timestamp
    created_str = db_query(f'SELECT UNIX_TIMESTAMP(created) FROM security_service_audits WHERE id={newest_id}')
    created_ts = int(created_str) if created_str else 0
    
    # Only consider it valid if created after task start
    if created_ts >= task_start:
        audit_data['audit_found'] = True
        audit_data['id'] = newest_id
        audit_data['created_ts'] = created_ts
        
        # Fetch fields
        audit_data['service_id'] = db_query(f'SELECT security_service_id FROM security_service_audits WHERE id={newest_id}')
        audit_data['description'] = db_query(f'SELECT description FROM security_service_audits WHERE id={newest_id}')
        audit_data['planned_date'] = db_query(f'SELECT planned_date FROM security_service_audits WHERE id={newest_id}')
        audit_data['start_date'] = db_query(f'SELECT start_date FROM security_service_audits WHERE id={newest_id}')
        audit_data['end_date'] = db_query(f'SELECT end_date FROM security_service_audits WHERE id={newest_id}')
        audit_data['result'] = db_query(f'SELECT result FROM security_service_audits WHERE id={newest_id}')

# Result object
result = {
    'initial_count': initial_count,
    'current_count': current_count,
    'target_service_id': target_service_id,
    'audit': audit_data,
    'timestamp': str(task_start)
}

# Write to JSON file
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 4. Handle permissions so verifier can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="