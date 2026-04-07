#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Use Python to safely extract database state into JSON
# This avoids bash array/quoting hell with varying schema columns
python3 - << 'EOF'
import subprocess
import json
import csv
from io import StringIO

def get_sql(query):
    try:
        res = subprocess.run(
            ['mysql', '-u', 'freemed', '-pfreemed', 'freemed', '-e', query],
            capture_output=True, text=True, timeout=10
        )
        return res.stdout.strip()
    except Exception as e:
        print(f"Error running SQL: {e}")
        return ""

def read_file(path, default=""):
    try:
        with open(path, 'r') as f:
            return f.read().strip()
    except:
        return default

# Get max ID from before task
max_id_str = read_file('/tmp/initial_max_procrec_id.txt', "0")
try:
    max_id = int(max_id_str)
except:
    max_id = 0

# Fetch new records
raw_csv = get_sql(f"SELECT * FROM procrec WHERE id > {max_id}")
new_records = []
if raw_csv:
    reader = csv.DictReader(StringIO(raw_csv), delimiter='\t')
    for row in reader:
        new_records.append(row)

# Get target patient ID
target_patient_id = read_file('/tmp/task_patient_id.txt', "0")

# Package into JSON
result = {
    "new_records": new_records,
    "target_patient_id": target_patient_id,
    "task_start": read_file('/tmp/task_start_time.txt', "0"),
    "task_end": read_file('/tmp/task_end_time.txt', "0"),
    "screenshot_exists": True
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported task_result.json successfully")
EOF

# Ensure permissions are correct
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="