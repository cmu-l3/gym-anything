#!/bin/bash
set -e

echo "=== Exporting Add Custom Lead Fields results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_FIELD_COUNT=$(cat /tmp/initial_field_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query database for current state
# We use a python script to safely execute SQL and format as JSON
# to avoid parsing issues with bash and SQL output
cat > /tmp/query_vicidial.py << 'PYEOF'
import json
import subprocess
import sys

def run_query(query):
    cmd = [
        "docker", "exec", "vicidial", 
        "mysql", "-ucron", "-p1234", "-D", "asterisk", 
        "-N", "-e", query
    ]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return result.decode('utf-8').strip()
    except subprocess.CalledProcessError:
        return ""

def get_fields_json(list_id):
    # Get raw fields data
    query = f"SELECT field_name, field_label, field_type, field_options, field_size FROM vicidial_lists_fields WHERE list_id='{list_id}'"
    raw_data = run_query(query)
    
    fields = []
    if raw_data:
        for line in raw_data.split('\n'):
            parts = line.split('\t')
            if len(parts) >= 3:
                fields.append({
                    "name": parts[0],
                    "label": parts[1],
                    "type": parts[2],
                    "options": parts[3] if len(parts) > 3 else "",
                    "size": parts[4] if len(parts) > 4 else ""
                })
    return fields

def check_table_exists(table_name):
    query = f"SELECT COUNT(*) FROM information_schema.tables WHERE table_name='{table_name}'"
    res = run_query(query)
    return res == "1"

def check_table_columns(table_name):
    query = f"SHOW COLUMNS FROM {table_name}"
    raw = run_query(query)
    columns = []
    if raw:
        for line in raw.split('\n'):
            columns.append(line.split('\t')[0])
    return columns

results = {
    "list_id": "8501",
    "fields": get_fields_json("8501"),
    "custom_table_exists": check_table_exists("custom_8501"),
    "custom_table_columns": check_table_columns("custom_8501")
}

print(json.dumps(results, indent=2))
PYEOF

# Run the python script and save output
python3 /tmp/query_vicidial.py > /tmp/db_state.json

# Merge into final result JSON
cat > /tmp/query_merger.py << 'PYEOF'
import json
import time

try:
    with open('/tmp/db_state.json', 'r') as f:
        db_state = json.load(f)
except:
    db_state = {}

task_start = 0
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = int(f.read().strip())
except:
    pass
    
initial_count = 0
try:
    with open('/tmp/initial_field_count.txt', 'r') as f:
        initial_count = int(f.read().strip())
except:
    pass

final_result = {
    "task_start": task_start,
    "task_end": int(time.time()),
    "initial_field_count": initial_count,
    "db_state": db_state,
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f, indent=2)
PYEOF

python3 /tmp/query_merger.py

# Cleanup temp
rm -f /tmp/query_vicidial.py /tmp/query_merger.py /tmp/db_state.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="