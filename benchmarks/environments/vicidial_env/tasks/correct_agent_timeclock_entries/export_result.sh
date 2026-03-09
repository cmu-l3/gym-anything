#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the relevant records
# We need:
# 1. Feb 24 LOGOUT record for user 7001
# 2. Feb 25 LOGIN record for user 7001

echo "Querying database for results..."

# We select specific columns to verify: event, event_date, manager_user, last_stats_update
# We output as tab-separated values to easily parse or JSON directly if possible.
# Since mysql doesn't output JSON natively in older versions easily, we'll use a python script to format it.

cat > /tmp/query_results.py << 'PYEOF'
import subprocess
import json
import sys

def run_query(query):
    cmd = ["docker", "exec", "vicidial", "mysql", "-ucron", "-p1234", "-D", "asterisk", "-N", "-B", "-e", query]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode('utf-8')
        return result.strip()
    except subprocess.CalledProcessError:
        return ""

def get_record(user, date_str, event_type):
    # event_date is a datetime, we search by matching the date part
    query = f"SELECT event_date, manager_user, event_epoch FROM vicidial_timeclock_log WHERE user='{user}' AND event='{event_type}' AND event_date LIKE '{date_str}%' LIMIT 1"
    output = run_query(query)
    if not output:
        return None
    parts = output.split('\t')
    if len(parts) >= 3:
        return {
            "event_date": parts[0],
            "manager_user": parts[1],
            "event_epoch": parts[2]
        }
    return None

results = {
    "feb24_logout": get_record("7001", "2026-02-24", "LOGOUT"),
    "feb25_login": get_record("7001", "2026-02-25", "LOGIN"),
    "screenshot_path": "/tmp/task_final.png"
}

print(json.dumps(results))
PYEOF

# Run the python script and save output
python3 /tmp/query_results.py > /tmp/task_result.json

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="