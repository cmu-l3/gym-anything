#!/bin/bash
# Export script for Record Patient Vitals task

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve setup variables
PID=$(cat /tmp/target_patient_id.txt 2>/dev/null || echo "0")
INIT_COUNT=$(cat /tmp/initial_vitals_count.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Patient ID: $PID | Initial Count: $INIT_COUNT"

# Use a lightweight python script to securely query the DB and dump to JSON
# This avoids bash quoting hell and robustly handles schema variations
cat > /tmp/export_db.py << 'EOF'
import subprocess
import json
import sys

pid = sys.argv[1]
init_count = int(sys.argv[2])
task_start = int(sys.argv[3])

def run_sql(query, use_G=False):
    cmd = ["mysql", "-u", "freemed", "-pfreemed", "freemed", "-N", "-B"]
    if use_G:
        cmd.extend(["-e", query + "\\G"])
    else:
        cmd.extend(["-e", query])
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

# Discover exact patient column name dynamically
cols_raw = run_sql("SHOW COLUMNS FROM vitals")
cols = [line.split('\t')[0] for line in cols_raw.split('\n') if line]

pat_col = "patient"
if "vpatient" in cols: pat_col = "vpatient"
elif "ppatient" in cols: pat_col = "ppatient"

# Get current count
curr_count_raw = run_sql(f"SELECT COUNT(*) FROM vitals WHERE {pat_col}={pid}")
curr_count = int(curr_count_raw) if curr_count_raw.isdigit() else 0

row = {}
if curr_count > 0:
    # Get the newest row as key-value pairs using \G
    row_raw = run_sql(f"SELECT * FROM vitals WHERE {pat_col}={pid} ORDER BY id DESC LIMIT 1", use_G=True)
    for line in row_raw.split('\n'):
        line = line.strip()
        if line.startswith('*') or ':' not in line: 
            continue
        key, val = line.split(':', 1)
        row[key.strip()] = val.strip()

result = {
    "patient_id": pid,
    "initial_count": init_count,
    "current_count": curr_count,
    "task_start_time": task_start,
    "newest_vital": row,
    "patient_column_used": pat_col
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Execute the python script
python3 /tmp/export_db.py "$PID" "$INIT_COUNT" "$TASK_START"

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export Complete ==="