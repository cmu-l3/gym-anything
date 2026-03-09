#!/bin/bash
echo "=== Exporting Configure X12 Partner Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the results
# We look for ANY record created/modified that matches the name 'Availity'
# We output it as a JSON object
echo "Querying x12_partners table..."

# Use python to safely fetch and format the DB result as JSON to avoid bash quoting hell
python3 -c "
import subprocess
import json
import sys

def run_query(sql):
    try:
        cmd = ['docker', 'exec', 'librehealth-db', 'mysql', '-u', 'libreehr', '-ps3cret', 'libreehr', '-N', '-e', sql]
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return result
    except Exception:
        return ''

# Get final count
final_count_str = run_query('SELECT COUNT(*) FROM x12_partners')
final_count = int(final_count_str) if final_count_str.isdigit() else 0

# Get the specific record details
# Columns: name, id_number, x12_sender_id, x12_receiver_id, processing_format, version
fields_sql = \"SELECT name, id_number, x12_sender_id, x12_receiver_id, processing_format, version FROM x12_partners WHERE name LIKE '%Availity%' LIMIT 1\"
record_str = run_query(fields_sql)

record_found = False
record_data = {}

if record_str:
    record_found = True
    parts = record_str.split('\t')
    if len(parts) >= 6:
        record_data = {
            'name': parts[0],
            'id_number': parts[1],
            'sender_id': parts[2],
            'receiver_id': parts[3],
            'format': parts[4],
            'version': parts[5]
        }

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': int('$INITIAL_COUNT'),
    'final_count': final_count,
    'record_found': record_found,
    'record_data': record_data,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so the host can read it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json