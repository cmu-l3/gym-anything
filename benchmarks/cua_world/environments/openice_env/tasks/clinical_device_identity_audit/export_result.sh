#!/bin/bash
echo "=== Exporting Clinical Device Identity Audit Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# File Validation
TARGET_FILE="/home/ga/Desktop/device_identity_map.csv"
FILE_EXISTS="false"
FILE_MTIME="0"
FILE_CONTENT=""

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    # Read file content, escaping quotes/backslashes for JSON safety
    FILE_CONTENT=$(cat "$TARGET_FILE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
fi

# Extract Device UUIDs from OpenICE Log
# We look for UUID patterns (8-4-4-4-12 hex chars) in the log lines added during the task
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")

# Regex for UUID: 8-4-4-4-12 hex chars
UUID_REGEX="[0-9a-fA-F]\{8\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{12\}"

# Extract new logs
NEW_LOGS=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null)

# Find all UUIDs mentioned in logs associated with device creation/start
# We grep for lines with "Device" and a UUID, then extract just the UUID
# This provides the Ground Truth list of valid UUIDs for this session
FOUND_UUIDS=$(echo "$NEW_LOGS" | grep -i "Device" | grep -o "$UUID_REGEX" | sort | uniq | tr '\n' ',' | sed 's/,$//')

# Also try to map UUIDs to types if the log line format permits
# Example log line: "Created DeviceAdapter [Multiparameter Monitor] with ID [uuid]"
# We capture specific lines to help the verifier debug
LOG_EVIDENCE=$(echo "$NEW_LOGS" | grep -iE "Created|Device|Adapter|Started" | grep -iE "Multiparameter|Pulse|Infusion|Monitor|Pump" | tail -n 20 | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')

# OpenICE Status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Window Count Check (proxy for device creation)
INITIAL_WINDOWS=$(cat /tmp/initial_window_count 2>/dev/null || echo "0")
FINAL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | wc -l)
WINDOW_INCREASE=$((FINAL_WINDOWS - INITIAL_WINDOWS))

# Create Result JSON
# Using a python script for safer JSON generation with complex strings
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_exists': $FILE_EXISTS,
    'file_mtime': $FILE_MTIME,
    'file_content': \"$FILE_CONTENT\",
    'ground_truth_uuids': \"$FOUND_UUIDS\".split(',') if \"$FOUND_UUIDS\" else [],
    'log_evidence': \"$LOG_EVIDENCE\",
    'openice_running': $OPENICE_RUNNING,
    'window_increase': $WINDOW_INCREASE
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Permissions fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/task_result.json