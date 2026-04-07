#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting configure_lms_setup results ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query DB securely to gather resulting state
python3 << 'PYEOF'
import json
import time
import subprocess
import os

def db_query(query):
    result = subprocess.run(
        ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
         '-psebserver123', 'SEBServer', '-N', '-e', query],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()

def db_query_rows(query):
    res = db_query(query)
    return [r.strip() for r in res.split('\n') if r.strip()]

start_time = 0.0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    pass

# Load baseline counts
initial_count = 0
try:
    with open('/tmp/initial_lms_count.txt', 'r') as f:
        initial_count = int(f.read().strip())
except Exception:
    pass

initial_ids = set()
try:
    with open('/tmp/initial_lms_ids.txt', 'r') as f:
        initial_ids = set(f.read().strip().split('\n'))
except Exception:
    pass

# Current count
current_count_str = db_query("SELECT COUNT(*) FROM lms_setup;")
current_count = int(current_count_str) if current_count_str.isdigit() else 0

# Check newly created records
all_current_ids = db_query_rows("SELECT id FROM lms_setup;")
new_ids = [idx for idx in all_current_ids if idx and idx not in initial_ids]

name_found = False
type_found = False
url_found = False
client_found = False

# Evaluate fields in all new records (or all records if none are uniquely "new")
ids_to_check = new_ids if new_ids else all_current_ids

for record_id in ids_to_check:
    row_data = db_query(f"SELECT * FROM lms_setup WHERE id = {record_id};")
    if row_data:
        row_lower = row_data.lower()
        if "state university moodle" in row_lower:
            name_found = True
        if "moodle" in row_lower:
            type_found = True
        if "moodle.stateuniversity.edu" in row_lower:
            url_found = True
        if "seb-server-integration" in row_lower:
            client_found = True

result = {
    'timestamp': time.time(),
    'task_start_time': start_time,
    'task_duration_seconds': time.time() - start_time,
    'initial_count': initial_count,
    'current_count': current_count,
    'new_records_created': len(new_ids),
    'name_found': name_found,
    'type_found': type_found,
    'url_found': url_found,
    'client_found': client_found,
}

# Write out safely
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="