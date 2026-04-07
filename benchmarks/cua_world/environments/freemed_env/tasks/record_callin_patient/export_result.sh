#!/bin/bash
# Export script: record_callin_patient

echo "=== Exporting record_callin_patient task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_callin_end.png

# Get final counts from the database
export FINAL_CALLIN_COUNT=$(freemed_query "SELECT COUNT(*) FROM callin" 2>/dev/null || echo "0")
export FINAL_PATIENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM patient" 2>/dev/null || echo "0")

# Dump the most recently added rows to check for our data
# We dump the raw text to avoid strict column name dependencies
freemed_query "SELECT * FROM callin ORDER BY 1 DESC LIMIT 5" > /tmp/callin_dump.txt 2>/dev/null || true
freemed_query "SELECT * FROM patient ORDER BY 1 DESC LIMIT 5" > /tmp/patient_dump.txt 2>/dev/null || true

# Construct JSON export securely via Python
python3 -c "
import json
import os

def read_file(path):
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read()
    except Exception:
        return ''

callin_dump = read_file('/tmp/callin_dump.txt')
patient_dump = read_file('/tmp/patient_dump.txt')

try:
    with open('/tmp/initial_counts.json', 'r') as f:
        initial = json.load(f)
except Exception:
    initial = {'callin': 0, 'patient': 0, 'start_time': 0}

result = {
    'callin_dump': callin_dump,
    'patient_dump': patient_dump,
    'initial_callin_count': initial.get('callin', 0),
    'initial_patient_count': initial.get('patient', 0),
    'final_callin_count': int(os.environ.get('FINAL_CALLIN_COUNT', 0)),
    'final_patient_count': int(os.environ.get('FINAL_PATIENT_COUNT', 0)),
    'task_start_time': initial.get('start_time', 0),
    'export_time': int(os.popen('date +%s').read().strip())
}

# Write securely, then set permissions for verifier to read
out_path = '/tmp/task_result.json'
with open(out_path, 'w') as f:
    json.dump(result, f)
os.chmod(out_path, 0o666)
"

echo "Database dump generated and saved to /tmp/task_result.json"
echo "=== Export complete ==="