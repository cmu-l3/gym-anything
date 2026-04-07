#!/bin/bash
# export_result.sh - Post-task hook for configure_edge_flags
# Extracts browser state and configuration file for verification

echo "=== Exporting configure_edge_flags results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to ensure 'Local State' is flushed to disk
# Chromium-based browsers write to Local State on change, but killing ensures no pending writes.
echo "Stopping Microsoft Edge to flush state..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# 3. Read Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# 4. Check Configuration Document
CONFIG_FILE="/home/ga/Desktop/edge_flags_config.txt"
CONFIG_EXISTS="false"
CONFIG_CONTENT=""
CONFIG_CREATED_DURING_TASK="false"

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE")
    
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_CREATED_DURING_TASK="true"
    fi
    
    # Read content (limit size)
    CONFIG_CONTENT=$(cat "$CONFIG_FILE" | head -c 1000)
fi

# 5. Extract Flags from Local State using Python
# We need to parse the JSON and extract the 'enabled_labs_experiments' list
LOCAL_STATE_FILE="/home/ga/.config/microsoft-edge/Local State"

python3 << PYEOF
import json
import os
import sys

result = {
    "task_start": $TASK_START,
    "export_time": $EXPORT_TIME,
    "config_file": {
        "exists": $CONFIG_EXISTS,
        "created_during_task": $CONFIG_CREATED_DURING_TASK,
        "content": """$CONFIG_CONTENT"""
    },
    "flags": []
}

local_state_path = "$LOCAL_STATE_FILE"

if os.path.exists(local_state_path):
    try:
        with open(local_state_path, 'r') as f:
            data = json.load(f)
        
        experiments = data.get('browser', {}).get('enabled_labs_experiments', [])
        result['flags'] = experiments
        print(f"Found {len(experiments)} active experiments")
    except Exception as e:
        result['error'] = str(e)
        print(f"Error reading Local State: {e}")
else:
    print("Local State file not found")

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# 6. Final cleanup (permissions)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="