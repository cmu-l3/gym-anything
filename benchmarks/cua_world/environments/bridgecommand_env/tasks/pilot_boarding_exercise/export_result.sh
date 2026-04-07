#!/bin/bash
echo "=== Exporting pilot_boarding_exercise result ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/p) Solent Pilot Boarding Exercise"
CHECKLIST_FILE="/home/ga/Documents/pilot_boarding_checklist.txt"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_DATA="$BC_DATA/bc5.ini"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Scenario Files
SCENARIO_EXISTS="false"
ENV_EXISTS="false"
OWN_EXISTS="false"
OTHER_EXISTS="false"
ENV_CONTENT=""
OWN_CONTENT=""
OTHER_CONTENT=""

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    if [ -f "$SCENARIO_DIR/environment.ini" ]; then
        ENV_EXISTS="true"
        ENV_CONTENT=$(cat "$SCENARIO_DIR/environment.ini" | base64 -w 0)
    fi
    if [ -f "$SCENARIO_DIR/ownship.ini" ]; then
        OWN_EXISTS="true"
        OWN_CONTENT=$(cat "$SCENARIO_DIR/ownship.ini" | base64 -w 0)
    fi
    if [ -f "$SCENARIO_DIR/othership.ini" ]; then
        OTHER_EXISTS="true"
        OTHER_CONTENT=$(cat "$SCENARIO_DIR/othership.ini" | base64 -w 0)
    fi
fi

# 3. Check Checklist File
CHECKLIST_EXISTS="false"
CHECKLIST_CONTENT=""
CHECKLIST_SIZE=0
CHECKLIST_MODIFIED="false"

if [ -f "$CHECKLIST_FILE" ]; then
    CHECKLIST_EXISTS="true"
    CHECKLIST_CONTENT=$(cat "$CHECKLIST_FILE" | base64 -w 0)
    CHECKLIST_SIZE=$(stat -c %s "$CHECKLIST_FILE")
    FILE_TIME=$(stat -c %Y "$CHECKLIST_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START_TIME" ]; then
        CHECKLIST_MODIFIED="true"
    fi
fi

# 4. Check bc5.ini Configuration
# BC reads from user config first, then data config. We'll check both.
CONFIG_CONTENT=""
if [ -f "$BC_CONFIG_USER" ]; then
    CONFIG_CONTENT=$(cat "$BC_CONFIG_USER" | base64 -w 0)
elif [ -f "$BC_CONFIG_DATA" ]; then
    CONFIG_CONTENT=$(cat "$BC_CONFIG_DATA" | base64 -w 0)
fi

# 5. Create JSON result using Python for safety
python3 -c "
import json
import os
import time

result = {
    'timestamp': time.time(),
    'scenario_dir_exists': '$SCENARIO_EXISTS' == 'true',
    'environment_ini': {
        'exists': '$ENV_EXISTS' == 'true',
        'content_b64': '$ENV_CONTENT'
    },
    'ownship_ini': {
        'exists': '$OWN_EXISTS' == 'true',
        'content_b64': '$OWN_CONTENT'
    },
    'othership_ini': {
        'exists': '$OTHER_EXISTS' == 'true',
        'content_b64': '$OTHER_CONTENT'
    },
    'checklist': {
        'exists': '$CHECKLIST_EXISTS' == 'true',
        'modified_during_task': '$CHECKLIST_MODIFIED' == 'true',
        'size': int('$CHECKLIST_SIZE'),
        'content_b64': '$CHECKLIST_CONTENT'
    },
    'bc5_config': {
        'content_b64': '$CONFIG_CONTENT'
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# 6. Make result accessible
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"