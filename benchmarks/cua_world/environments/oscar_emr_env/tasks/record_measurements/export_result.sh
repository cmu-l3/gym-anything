#!/bin/bash
# Export script for Record Measurements task
# Queries the database for measurements and exports to JSON

echo "=== Exporting Record Measurements Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DEMO_NO=$(cat /tmp/task_patient_demo_no.txt 2>/dev/null || echo "")

echo "Task timing: $TASK_START -> $TASK_END"
echo "Patient demographic_no: $DEMO_NO"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get initial measurement count
INITIAL_COUNT=$(cat /tmp/initial_measurement_count.txt 2>/dev/null || echo "0")

# Use a Python script to robustly query and format the JSON
# This avoids fragile bash string manipulation with SQL output
python3 -c "
import subprocess
import json
import sys
import time

def oscar_query(sql):
    try:
        cmd = ['docker', 'exec', 'oscar-db', 'mysql', '-u', 'oscar', '-poscar', 'oscar', '-N', '-e', sql]
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.stdout.strip()
    except Exception as e:
        return ''

demo_no = '$DEMO_NO'
task_start = $TASK_START
initial_count = int('$INITIAL_COUNT')

# 1. Get current count
count_res = oscar_query(f\"SELECT COUNT(*) FROM measurements WHERE demographicNo='{demo_no}'\")
current_count = int(count_res) if count_res.isdigit() else 0

# 2. Get measurements entered during the task (with a small buffer for clock skew)
# We select type, value (dataField), and unix timestamp of entry
query = f\"\"\"
    SELECT type, dataField, UNIX_TIMESTAMP(dateEntered)
    FROM measurements
    WHERE demographicNo='{demo_no}'
    ORDER BY dateEntered DESC LIMIT 20
\"\"\"
raw_measurements = oscar_query(query)

measurements = []
if raw_measurements:
    for line in raw_measurements.split('\n'):
        parts = line.split('\t')
        if len(parts) >= 3:
            m_type = parts[0]
            m_val = parts[1]
            m_ts = int(parts[2])
            
            # Check if this is a new measurement (created after task start)
            # Allow 60s grace period in case of slight clock differences
            is_new = m_ts >= (task_start - 60)
            
            measurements.append({
                'type': m_type,
                'value': m_val,
                'timestamp': m_ts,
                'is_new': is_new
            })

# 3. Check if app is running
app_running = False
try:
    # simple check if firefox is running
    subprocess.run(['pgrep', '-f', 'firefox'], check=True, stdout=subprocess.DEVNULL)
    app_running = True
except subprocess.CalledProcessError:
    pass

result = {
    'demo_no': demo_no,
    'task_start': task_start,
    'initial_count': initial_count,
    'current_count': current_count,
    'measurements': measurements,
    'app_running': app_running,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print('Export successful')
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="