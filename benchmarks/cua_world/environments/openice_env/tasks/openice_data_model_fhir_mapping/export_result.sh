#!/bin/bash
set -e
echo "=== Exporting results for openice_data_model_fhir_mapping ==="

export DISPLAY=:1
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size.txt 2>/dev/null || echo "0")
INITIAL_WINDOW_COUNT=$(cat /tmp/initial_window_count.txt 2>/dev/null || echo "0")

# --- Helper to read file content safely for JSON ---
read_file_content() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        # Read file, escape backslashes and quotes, replace newlines with \n
        cat "$file_path" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))'
    else
        echo "null"
    fi
}

# --- Data Dictionary Analysis ---
DD_FILE="/home/ga/Desktop/openice_data_dictionary.txt"
DD_EXISTS="false"
DD_SIZE=0
DD_MTIME=0
DD_CONTENT="null"

if [ -f "$DD_FILE" ]; then
    DD_EXISTS="true"
    DD_SIZE=$(stat -c%s "$DD_FILE" 2>/dev/null || echo "0")
    DD_MTIME=$(stat -c%Y "$DD_FILE" 2>/dev/null || echo "0")
    DD_CONTENT=$(read_file_content "$DD_FILE")
fi

# --- FHIR Mapping Analysis ---
FHIR_FILE="/home/ga/Desktop/fhir_mapping_proposal.txt"
FHIR_EXISTS="false"
FHIR_SIZE=0
FHIR_MTIME=0
FHIR_CONTENT="null"

if [ -f "$FHIR_FILE" ]; then
    FHIR_EXISTS="true"
    FHIR_SIZE=$(stat -c%s "$FHIR_FILE" 2>/dev/null || echo "0")
    FHIR_MTIME=$(stat -c%Y "$FHIR_FILE" 2>/dev/null || echo "0")
    FHIR_CONTENT=$(read_file_content "$FHIR_FILE")
fi

# --- Device Creation Evidence ---
DEVICE_CREATED="false"
LOG_FILE="/home/ga/openice/logs/openice.log"

# Check new log lines
if [ -f "$LOG_FILE" ]; then
    NEW_LOG_LINES=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")
    if echo "$NEW_LOG_LINES" | grep -qiE "simulated|simulator|device.*adapter|multiparameter|monitor|infusion|pulse.?ox"; then
        DEVICE_CREATED="true"
    fi
fi

# Check window titles for device adapters
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
FINAL_WINDOW_COUNT=$(echo "$CURRENT_WINDOWS" | wc -l)
if echo "$CURRENT_WINDOWS" | grep -qiE "simulated|monitor|device|adapter|pump|pulse"; then
    DEVICE_CREATED="true"
fi

# Also check simply if window count increased by at least 1 (simulated device creates a new window)
if [ "$FINAL_WINDOW_COUNT" -gt "$INITIAL_WINDOW_COUNT" ]; then
    # Weak signal, but combined with file evidence it helps
    # We won't set DEVICE_CREATED solely on this, but track it
    WINDOW_INCREASED="true"
else
    WINDOW_INCREASED="false"
fi

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# --- Build Result JSON ---
# We use a python script to construct the JSON safely to handle large content strings
python3 -c "
import json
import sys

output = {
    'task_start_time': $TASK_START,
    'data_dictionary': {
        'exists': $DD_EXISTS,
        'size_bytes': $DD_SIZE,
        'mtime': $DD_MTIME,
        'content': $DD_CONTENT
    },
    'fhir_mapping': {
        'exists': $FHIR_EXISTS,
        'size_bytes': $FHIR_SIZE,
        'mtime': $FHIR_MTIME,
        'content': $FHIR_CONTENT
    },
    'device_created': $DEVICE_CREATED,
    'window_increased': $WINDOW_INCREASED,
    'initial_window_count': $INITIAL_WINDOW_COUNT,
    'final_window_count': $FINAL_WINDOW_COUNT
}

with open('/tmp/temp_result.json', 'w') as f:
    json.dump(output, f)
"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/temp_result.json

echo "=== Result export complete ==="
echo "Data Dictionary exists: $DD_EXISTS"
echo "FHIR Mapping exists: $FHIR_EXISTS"
echo "Device Created: $DEVICE_CREATED"