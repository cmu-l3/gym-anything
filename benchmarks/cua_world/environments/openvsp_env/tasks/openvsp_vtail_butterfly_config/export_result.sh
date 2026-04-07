#!/bin/bash
# Export script for openvsp_vtail_butterfly_config task
# Checks for the new file and packages its contents for the verifier

set -e
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/openvsp_vtail_result.json"
EXPECTED_FILE="/home/ga/Documents/OpenVSP/eCRM001_vtail_study.vsp3"
START_TIME_FILE="/tmp/task_start_timestamp"

echo "=== Exporting result for openvsp_vtail_butterfly_config ==="

# Take final screenshot as evidence
take_screenshot /tmp/task_final_screenshot.png

# Safely close OpenVSP to flush any pending file writes
kill_openvsp
sleep 1

# Extract task start time
TASK_START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")

# Write file details and content to JSON for the Python verifier
python3 << PYEOF
import json, os

expected_file = '$EXPECTED_FILE'
task_start = int('$TASK_START')

result = {
    'task_start_time': task_start,
    'file_exists': False,
    'file_mtime': 0,
    'file_size': 0,
    'file_content': ''
}

if os.path.isfile(expected_file):
    result['file_exists'] = True
    result['file_mtime'] = int(os.path.getmtime(expected_file))
    result['file_size'] = os.path.getsize(expected_file)
    
    # Read the XML content
    try:
        with open(expected_file, 'r', errors='replace') as f:
            result['file_content'] = f.read()
    except Exception as e:
        print(f"Error reading file content: {e}")

# Save the result
with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)

print(f"Exported result: exists={result['file_exists']}, size={result['file_size']} bytes")
if result['file_exists']:
    if result['file_mtime'] > task_start:
        print("File was successfully modified/created AFTER task started (Anti-gaming check passed).")
    else:
        print("WARNING: File mtime is before task start!")
PYEOF

echo "=== Export complete ==="