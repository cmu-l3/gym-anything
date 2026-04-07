#!/bin/bash
echo "=== Exporting Emergency Towing Exercise Results ==="

# Paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) Dover Strait ETV Exercise"
DOC_FILE="/home/ga/Documents/emergency_towing_procedure.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Collect Configuration Data (bc5.ini)
# Agent might edit user config OR global config. We check both.
BC5_CONTENT=""
if [ -f "/home/ga/.config/Bridge Command/bc5.ini" ]; then
    BC5_CONTENT=$(cat "/home/ga/.config/Bridge Command/bc5.ini")
elif [ -f "/opt/bridgecommand/bc5.ini" ]; then
    BC5_CONTENT=$(cat "/opt/bridgecommand/bc5.ini")
fi

# 3. Collect Scenario Data
ENV_CONTENT=""
OWN_CONTENT=""
OTHER_CONTENT=""
SCENARIO_CREATED_TIME=0

if [ -d "$SCENARIO_DIR" ]; then
    # Check creation time of environment.ini to ensure it wasn't pre-existing
    if [ -f "$SCENARIO_DIR/environment.ini" ]; then
        ENV_CONTENT=$(cat "$SCENARIO_DIR/environment.ini")
        SCENARIO_CREATED_TIME=$(stat -c %Y "$SCENARIO_DIR/environment.ini")
    fi
    [ -f "$SCENARIO_DIR/ownship.ini" ] && OWN_CONTENT=$(cat "$SCENARIO_DIR/ownship.ini")
    [ -f "$SCENARIO_DIR/othership.ini" ] && OTHER_CONTENT=$(cat "$SCENARIO_DIR/othership.ini")
fi

# 4. Collect Document Data
DOC_CONTENT=""
DOC_WORD_COUNT=0
DOC_CREATED_TIME=0

if [ -f "$DOC_FILE" ]; then
    # Read first 5000 chars to avoid massive JSON
    DOC_CONTENT=$(head -c 5000 "$DOC_FILE")
    DOC_WORD_COUNT=$(wc -w < "$DOC_FILE")
    DOC_CREATED_TIME=$(stat -c %Y "$DOC_FILE")
fi

# 5. Construct JSON Result
# Using python to safely escape strings for JSON
python3 -c "
import json
import os

try:
    result = {
        'task_start_time': $TASK_START,
        'scenario': {
            'exists': os.path.isdir('$SCENARIO_DIR'),
            'created_timestamp': $SCENARIO_CREATED_TIME,
            'environment_ini': '''$ENV_CONTENT''',
            'ownship_ini': '''$OWN_CONTENT''',
            'othership_ini': '''$OTHER_CONTENT'''
        },
        'config': {
            'bc5_ini': '''$BC5_CONTENT'''
        },
        'document': {
            'exists': os.path.isfile('$DOC_FILE'),
            'created_timestamp': $DOC_CREATED_TIME,
            'word_count': $DOC_WORD_COUNT,
            'content': '''$DOC_CONTENT'''
        }
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
except Exception as e:
    print(f'Error creating JSON: {e}')
"

# Set permissions so verifier can read it
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="