#!/bin/bash
set -e

echo "=== Exporting Configure State Call Times result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# We will use a python script to query the database and export clean JSON
# This avoids fragile bash parsing of MySQL output
cat > /tmp/export_db_state.py << 'PYEOF'
import subprocess
import json
import sys

def run_query(query):
    cmd = [
        "docker", "exec", "vicidial", 
        "mysql", "-ucron", "-p1234", "-D", "asterisk", 
        "-N", "-B", "-e", query
    ]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
        rows = []
        if result.strip():
            for line in result.strip().split('\n'):
                rows.append(line.split('\t'))
        return rows
    except Exception as e:
        return []

data = {
    "call_times": {},
    "state_call_times": []
}

# 1. Query Call Times
# We fetch ID, Name, Default Start, Default Stop
ct_query = "SELECT call_time_id, call_time_name, ct_default_start, ct_default_stop FROM vicidial_call_times WHERE call_time_id IN ('FL_SAFE', 'NV_SAFE')"
ct_rows = run_query(ct_query)
for row in ct_rows:
    if len(row) >= 4:
        data["call_times"][row[0]] = {
            "name": row[1],
            "start": row[2],
            "stop": row[3]
        }

# 2. Query State Call Times
# We need to find the rules associated with US_STRICT_26
# Table vicidial_state_call_times usually contains the rules.
# Columns might vary, but typically: state_call_time_id, state_call_time_state, state_call_time_name (or similar)
# We select all columns to be safe and will filter in python
sct_query = "SELECT * FROM vicidial_state_call_times WHERE state_call_time_id = 'US_STRICT_26'"
# Note: Since we don't know exact column indices, we'll try to map headers if possible, 
# but usually with -N we don't get headers.
# Let's try to get headers first.
headers_cmd = [
    "docker", "exec", "vicidial", 
    "mysql", "-ucron", "-p1234", "-D", "asterisk", 
    "-B", "-e", "SELECT * FROM vicidial_state_call_times LIMIT 1"
]
try:
    headers_res = subprocess.check_output(headers_cmd, stderr=subprocess.DEVNULL).decode('utf-8')
    headers = headers_res.split('\n')[0].split('\t')
except:
    headers = []

sct_rows = run_query(sct_query)
formatted_sct = []

for row in sct_rows:
    record = {}
    if len(headers) == len(row):
        for i, h in enumerate(headers):
            record[h] = row[i]
    else:
        # Fallback if headers fail: store raw list
        record["raw"] = row
    formatted_sct.append(record)

data["state_call_times"] = formatted_sct

# Add timestamp
import time
data["export_timestamp"] = time.time()

print(json.dumps(data, indent=2))
PYEOF

# Run the python script
python3 /tmp/export_db_state.py > /tmp/task_result.json

echo "Exported JSON size:"
stat -c %s /tmp/task_result.json

# Cleanup
rm -f /tmp/export_db_state.py 2>/dev/null || true

echo "=== Export complete ==="