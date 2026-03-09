#!/bin/bash
set -e
echo "=== Exporting task results: create_call_time_restriction ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Taking final screenshot..."
take_screenshot /tmp/task_final.png

# Check if application was running
APP_RUNNING="false"
if pgrep -f firefox > /dev/null; then
  APP_RUNNING="true"
fi

# Query the database for the call time record
echo "Querying database for EASTERN_TCPA..."

# We use a comprehensive query to get all fields needed for verification
# Outputting as a single line of tab-separated values for easy parsing, 
# or handling it via python within the script to generate JSON.
# Here we'll generate a JSON directly using python inside the script for robustness.

cat > /tmp/query_result.py << 'PYEOF'
import subprocess
import json
import sys

def run_query(query):
    cmd = [
        "docker", "exec", "vicidial", "mysql", "-ucron", "-p1234", "-D", "asterisk", 
        "-N", "-e", query
    ]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return result.decode('utf-8').strip()
    except subprocess.CalledProcessError:
        return ""

columns = [
    "call_time_id", "call_time_name", "call_time_comments", 
    "ct_default_start", "ct_default_stop",
    "ct_sunday_start", "ct_sunday_stop",
    "ct_monday_start", "ct_monday_stop",
    "ct_tuesday_start", "ct_tuesday_stop",
    "ct_wednesday_start", "ct_wednesday_stop",
    "ct_thursday_start", "ct_thursday_stop",
    "ct_friday_start", "ct_friday_stop",
    "ct_saturday_start", "ct_saturday_stop"
]

select_clause = ", ".join(columns)
query = f"SELECT {select_clause} FROM vicidial_call_times WHERE call_time_id='EASTERN_TCPA'"

data_str = run_query(query)
record_found = False
record_data = {}

if data_str:
    record_found = True
    values = data_str.split('\t')
    if len(values) == len(columns):
        for i, col in enumerate(columns):
            # Try to convert numeric strings to integers for easier JSON handling
            val = values[i]
            if val.isdigit():
                record_data[col] = int(val)
            else:
                record_data[col] = val

initial_count = 0
try:
    with open('/tmp/initial_call_time_count.txt', 'r') as f:
        initial_count = int(f.read().strip())
except:
    pass

result = {
    "task_start": int(sys.argv[1]),
    "task_end": int(sys.argv[2]),
    "app_running": sys.argv[3] == "true",
    "record_found": record_found,
    "initial_count": initial_count,
    "record_data": record_data,
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported JSON result.")
PYEOF

# Run the python script to generate the JSON
python3 /tmp/query_result.py "$TASK_START" "$TASK_END" "$APP_RUNNING"

# Permissions fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json