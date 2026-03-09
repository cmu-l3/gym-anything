#!/bin/bash
echo "=== Exporting add_procedure_provider results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_pp_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Query current count
CURRENT_COUNT=$(librehealth_query "SELECT COUNT(*) FROM procedure_providers" 2>/dev/null || echo "0")

# 2. Query for the specific record
# We fetch the most recently added record that matches our criteria to verify details
# We output as a single line CSV-style or JSON-like string to parse later, 
# but using python to generate clean JSON is safer.

echo "Querying database for LabCorp record..."

# We will use python inside the export script to query DB via docker and format JSON safely
# This avoids bash string parsing issues with SQL results
python3 -c "
import subprocess
import json
import sys

def run_query(sql):
    cmd = ['docker', 'exec', 'librehealth-db', 'mysql', '-u', 'libreehr', '-ps3cret', 'libreehr', '-N', '-e', sql]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return res.decode('utf-8').strip()
    except:
        return ''

# Get record details
sql = \"SELECT name, npi, send_app_id, send_fac_id, recv_app_id, recv_fac_id, protocol, remote_host, active FROM procedure_providers WHERE name LIKE '%LabCorp%' OR npi='1234567893' ORDER BY ppid DESC LIMIT 1\"
row_str = run_query(sql)

record_found = False
record_data = {}

if row_str:
    record_found = True
    # mysql -N output is tab separated
    parts = row_str.split('\t')
    if len(parts) >= 8:
        record_data = {
            'name': parts[0],
            'npi': parts[1],
            'send_app_id': parts[2],
            'send_fac_id': parts[3],
            'recv_app_id': parts[4],
            'recv_fac_id': parts[5],
            'protocol': parts[6],
            'remote_host': parts[7],
            'active': parts[8] if len(parts) > 8 else '1'
        }

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': int('$INITIAL_COUNT'),
    'current_count': int('$CURRENT_COUNT'),
    'record_found': record_found,
    'record_data': record_data,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so the host can read it (via copy_from_env)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="