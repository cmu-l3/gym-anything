#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting document_patient_phone_call results ==="

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# 2. Load Ground Truth
if [ ! -f /tmp/task_ground_truth.json ]; then
    echo "ERROR: Ground truth file missing!"
    exit 1
fi

# Extract values using python for reliability
TARGET_PID=$(python3 -c "import json; print(json.load(open('/tmp/task_ground_truth.json'))['target_pid'])")
MED_NAME=$(python3 -c "import json; print(json.load(open('/tmp/task_ground_truth.json'))['medication'])")
INITIAL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/task_ground_truth.json'))['initial_note_count'])")
DB_START_TIME=$(python3 -c "import json; print(json.load(open('/tmp/task_ground_truth.json'))['db_start_time'])")

# 3. Query Database for NEW Notes
# We check for notes for this PID that have a higher ID than likely before, 
# AND were created after the start time.
# Note: pnotes table usually has 'date' column.
echo "Checking database for new notes for PID $TARGET_PID..."

# Get current count
CURRENT_COUNT=$(librehealth_query "SELECT COUNT(*) FROM pnotes WHERE pid=$TARGET_PID")

# Get the most recent note for this patient
# We fetch ID, Date, Body, Activity, User
# We use python to handle the SQL execution and JSON serialization of the result
# to strictly avoid bash quoting issues with the note body text.

python3 -c "
import json
import subprocess
import sys

def query(sql):
    cmd = ['docker', 'exec', 'librehealth-db', 'mysql', '-u', 'libreehr', '-ps3cret', 'libreehr', '-N', '-e', sql]
    try:
        return subprocess.check_output(cmd).decode('utf-8').strip()
    except:
        return ''

pid = $TARGET_PID
start_time = '$DB_START_TIME'
initial_count = $INITIAL_COUNT
current_count = $CURRENT_COUNT

# Fetch latest note for patient
# Assuming 'id' is auto-increment, higher id = newer
sql = f\"SELECT id, date, body, activity, user FROM pnotes WHERE pid={pid} ORDER BY id DESC LIMIT 1\"
raw_row = query(sql)

note_found = False
note_data = {}

if raw_row:
    parts = raw_row.split('\t')
    # Basic check: did count increase?
    # Or strict check: is date >= start_time? (Comparing SQL datetimes as strings works iso-8601)
    note_date = parts[1]
    
    # Check if this is actually a new note
    # We rely on count increase OR date being fresh
    is_new = (current_count > initial_count) or (note_date >= start_time)
    
    if is_new:
        note_found = True
        note_data = {
            'id': parts[0],
            'date': parts[1],
            'body': parts[2],
            'activity': parts[3], # 1 = active
            'user': parts[4]
        }

result = {
    'note_found': note_found,
    'note_data': note_data,
    'target_medication': '$MED_NAME',
    'initial_count': initial_count,
    'current_count': current_count,
    'screenshot_path': '/tmp/task_final.png',
    'screenshot_exists': $SCREENSHOT_EXISTS
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions so verify can read it
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="