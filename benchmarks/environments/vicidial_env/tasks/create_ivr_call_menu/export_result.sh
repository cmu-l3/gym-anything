#!/bin/bash
echo "=== Exporting Create IVR Call Menu Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if application is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Use Python to extraction detailed DB state securely
# This runs inside the VM and queries the Docker container
cat > /tmp/extract_db_state.py << 'PYEOF'
import subprocess
import json
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

def run_query_dict(query, fields):
    # Helper to get dict results (one row)
    raw = run_query(query)
    if not raw:
        return None
    values = raw.split('\t')
    if len(values) != len(fields):
        return None
    return dict(zip(fields, values))

def run_query_list_dict(query, fields):
    # Helper to get list of dicts (multiple rows)
    raw = run_query(query)
    if not raw:
        return []
    rows = []
    for line in raw.split('\n'):
        values = line.split('\t')
        if len(values) == len(fields):
            rows.append(dict(zip(fields, values)))
    return rows

result = {}

# 1. Check Menu Properties
menu_fields = ["menu_id", "menu_name", "menu_prompt", "menu_timeout", "menu_timeout_prompt", "menu_invalid_prompt", "menu_repeat"]
menu_query = f"SELECT {','.join(menu_fields)} FROM vicidial_call_menu WHERE menu_id='valley_health_main'"
menu_data = run_query_dict(menu_query, menu_fields)

result["menu_exists"] = (menu_data is not None)
result["menu_data"] = menu_data

# 2. Check Menu Options
if menu_data:
    opt_fields = ["option_value", "option_description", "route", "route_value", "route_context"]
    # Get all options for this menu
    opt_query = f"SELECT {','.join(opt_fields)} FROM vicidial_call_menu_options WHERE menu_id='valley_health_main'"
    options_data = run_query_list_dict(opt_query, opt_fields)
    result["options"] = options_data
else:
    result["options"] = []

# 3. Get total count for anti-gaming
count_query = "SELECT COUNT(*) FROM vicidial_call_menu"
try:
    current_count = int(run_query(count_query))
except:
    current_count = 0
result["current_menu_count"] = current_count

print(json.dumps(result, indent=2))
PYEOF

# Run the python script and capture output
python3 /tmp/extract_db_state.py > /tmp/db_state.json

# Read Initial Count
INITIAL_COUNT=$(cat /tmp/initial_menu_count.txt 2>/dev/null || echo "0")

# Compile Final Result JSON
# We merge the DB state with the task metadata
jq -n \
    --slurpfile db /tmp/db_state.json \
    --arg start "$TASK_START" \
    --arg end "$TASK_END" \
    --arg init_count "$INITIAL_COUNT" \
    --arg app_running "$APP_RUNNING" \
    '{
        task_start: $start,
        task_end: $end,
        initial_menu_count: $init_count,
        app_was_running: $app_running,
        db_state: $db[0]
    }' > /tmp/task_result.json

# Set permissions for the verifier to read
chmod 666 /tmp/task_result.json

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="