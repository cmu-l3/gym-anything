#!/bin/bash
echo "=== Exporting Fog Radar Assessment Result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/r) Solent Fog Radar Assessment"
WORKSHEET="$HOME/Documents/fog_assessment_worksheet.txt"
ANSWERS="$HOME/Documents/fog_assessment_answers.txt"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Scenario Data
echo "Extracting scenario data..."
SCENARIO_EXISTS=false
ENV_CONTENT=""
OWNSHIP_CONTENT=""
OTHERSHIP_CONTENT=""

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS=true
    [ -f "$SCENARIO_DIR/environment.ini" ] && ENV_CONTENT=$(cat "$SCENARIO_DIR/environment.ini")
    [ -f "$SCENARIO_DIR/ownship.ini" ] && OWNSHIP_CONTENT=$(cat "$SCENARIO_DIR/ownship.ini")
    [ -f "$SCENARIO_DIR/othership.ini" ] && OTHERSHIP_CONTENT=$(cat "$SCENARIO_DIR/othership.ini")
fi

# 3. Extract Config Data (bc5.ini)
# Check all potential locations
echo "Extracting config data..."
CONFIG_CONTENT=""
for cfg in "$HOME/.config/Bridge Command/bc5.ini" "$BC_DATA/bc5.ini" "$HOME/.Bridge Command/5.10/bc5.ini"; do
    if [ -f "$cfg" ]; then
        CONFIG_CONTENT+=$(echo "--- $cfg ---"; cat "$cfg"; echo -e "\n")
    fi
done

# 4. Extract Documents
echo "Extracting documents..."
WORKSHEET_EXISTS=false
ANSWERS_EXISTS=false
WORKSHEET_TEXT=""
ANSWERS_TEXT=""

if [ -f "$WORKSHEET" ]; then
    WORKSHEET_EXISTS=true
    WORKSHEET_TEXT=$(cat "$WORKSHEET")
fi

if [ -f "$ANSWERS" ]; then
    ANSWERS_EXISTS=true
    ANSWERS_TEXT=$(cat "$ANSWERS")
fi

# 5. Timestamp check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_NEW=false
# Check if scenario dir modification time is after start
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_MTIME=$(stat -c %Y "$SCENARIO_DIR" 2>/dev/null || echo "0")
    if [ "$SCENARIO_MTIME" -gt "$TASK_START" ]; then
        FILES_NEW=true
    fi
fi

# 6. Create JSON payload
# We use Python to robustly create JSON to avoid shell quoting hell
python3 -c "
import json
import os
import sys

def read_file(path):
    try:
        with open(path, 'r', errors='ignore') as f:
            return f.read()
    except:
        return ''

result = {
    'scenario_exists': $SCENARIO_EXISTS,
    'files_created_during_task': $FILES_NEW,
    'environment_ini': '''$ENV_CONTENT''',
    'ownship_ini': '''$OWNSHIP_CONTENT''',
    'othership_ini': '''$OTHERSHIP_CONTENT''',
    'config_dump': '''$CONFIG_CONTENT''',
    'worksheet': {
        'exists': $WORKSHEET_EXISTS,
        'content': '''$WORKSHEET_TEXT'''
    },
    'answers': {
        'exists': $ANSWERS_EXISTS,
        'content': '''$ANSWERS_TEXT'''
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so verifier can read it
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="