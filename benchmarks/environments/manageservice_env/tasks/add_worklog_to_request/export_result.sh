#!/bin/bash
echo "=== Exporting add_worklog_to_request results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_ID=$(cat /tmp/target_request_id.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_worklog_count.txt 2>/dev/null || echo "0")

# 3. Query Database for Worklogs on this Request
# In SDP, worklogs are often in 'Chargestable' linked by 'WorkOrderToCharge'
# Columns often include: ts_spent (time spent), description, createdtime, chargeid
# Note: ts_spent might be in milliseconds or minutes depending on version.
# We fetch relevant columns.
echo "Querying worklogs for Request ID: $TARGET_ID"

# Construct JSON output using Python to handle DB query and formatting safely
python3 << EOF
import json
import subprocess
import time

def run_db_query(sql):
    # Use the helper function from task_utils via bash invocation or direct psql
    # Since we are in python inside bash, let's just call sdp_db_exec
    cmd = ['bash', '-c', 'source /workspace/scripts/task_utils.sh && sdp_db_exec "' + sql + '"']
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return result
    except:
        return ""

target_id = "$TARGET_ID"
initial_count = int("$INITIAL_COUNT")
task_start = int("$TASK_START") * 1000  # Convert to ms for SDP timestamp comparison if needed

# Query to get worklogs:
# We join WorkOrderToCharge (maps WO to Charge) and ChargesTable (contains details)
# Note: Column names are case-sensitive in some Postgres setups, usually lowercase in SDP
sql = f"SELECT c.chargeid, c.ts_spent, c.description, c.createdtime, au.first_name FROM ChargesTable c JOIN WorkOrderToCharge woc ON c.chargeid = woc.chargeid LEFT JOIN AaaUser au ON c.technicianid = au.user_id WHERE woc.workorderid = {target_id} ORDER BY c.createdtime DESC"

# The output format from sdp_db_exec is usually pipe or raw text.
# Let's try to get it in a parseable format or just raw rows.
raw_data = run_db_query(sql)

worklogs = []
if raw_data:
    rows = raw_data.split('\n')
    for row in rows:
        parts = row.split('|')
        if len(parts) >= 3:
            # Basic parsing attempt (SDP schema varies, trying best effort)
            # Assuming sdp_db_exec returns pipe separated if configured, or just raw
            # If sdp_db_exec uses -A -t (unaligned, tuple only), default separator is pipe
            try:
                wl = {
                    "id": parts[0],
                    "time_spent": parts[1], # Could be ms or long
                    "description": parts[2],
                    "created_time": parts[3] if len(parts) > 3 else "0",
                    "technician": parts[4] if len(parts) > 4 else "unknown"
                }
                worklogs.append(wl)
            except:
                pass

current_count = len(worklogs)
new_worklogs_count = max(0, current_count - initial_count)

result = {
    "task_start_ts": task_start,
    "target_request_id": target_id,
    "initial_worklog_count": initial_count,
    "current_worklog_count": current_count,
    "new_worklogs_found": new_worklogs_count > 0,
    "worklogs": worklogs,
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported JSON result.")
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result contents:"
cat /tmp/task_result.json
echo "=== Export Complete ==="