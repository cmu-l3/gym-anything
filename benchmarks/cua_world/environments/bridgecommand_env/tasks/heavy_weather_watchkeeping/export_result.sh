#!/bin/bash
echo "=== Exporting heavy_weather_watchkeeping results ==="

# Define paths
BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/n) English Channel Heavy Weather Exercise"
DOCS_DIR="/home/ga/Documents"
BC_CONFIG_USER="/home/ga/.config/Bridge Command/bc5.ini"
BC_CONFIG_DATA="$BC_DATA/bc5.ini"
BC_CONFIG_LEGACY="/home/ga/.Bridge Command/5.10/bc5.ini"

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- DATA EXTRACTION ---

# 1. Scenario Files Existence & Content
SCENARIO_EXISTS=false
ENV_CONTENT=""
OWNSHIP_CONTENT=""
OTHERSHIP_CONTENT=""

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS=true
    
    if [ -f "$SCENARIO_DIR/environment.ini" ]; then
        ENV_CONTENT=$(cat "$SCENARIO_DIR/environment.ini" | base64 -w 0)
    fi
    
    if [ -f "$SCENARIO_DIR/ownship.ini" ]; then
        OWNSHIP_CONTENT=$(cat "$SCENARIO_DIR/ownship.ini" | base64 -w 0)
    fi
    
    if [ -f "$SCENARIO_DIR/othership.ini" ]; then
        OTHERSHIP_CONTENT=$(cat "$SCENARIO_DIR/othership.ini" | base64 -w 0)
    fi
fi

# 2. Configuration (bc5.ini)
# Agent might edit user config, legacy config, or system config. We check all.
# We prioritize the one most recently modified.

CONFIG_CONTENT=""
LATEST_MTIME=0

for cfg in "$BC_CONFIG_USER" "$BC_CONFIG_DATA" "$BC_CONFIG_LEGACY"; do
    if [ -f "$cfg" ]; then
        MTIME=$(stat -c %Y "$cfg")
        if [ "$MTIME" -gt "$LATEST_MTIME" ]; then
            LATEST_MTIME=$MTIME
            CONFIG_CONTENT=$(cat "$cfg" | base64 -w 0)
        fi
    fi
done

# 3. Documents
BRIEFING_EXISTS=false
BRIEFING_CONTENT=""
ORDERS_EXISTS=false
ORDERS_CONTENT=""

BRIEFING_FILE="$DOCS_DIR/met_briefing_heavy_weather.txt"
if [ -f "$BRIEFING_FILE" ]; then
    BRIEFING_EXISTS=true
    # Check timestamp to ensure created during task
    FILE_TIME=$(stat -c %Y "$BRIEFING_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        BRIEFING_CONTENT=$(cat "$BRIEFING_FILE" | base64 -w 0)
    fi
fi

ORDERS_FILE="$DOCS_DIR/masters_standing_orders.txt"
if [ -f "$ORDERS_FILE" ]; then
    ORDERS_EXISTS=true
    FILE_TIME=$(stat -c %Y "$ORDERS_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        ORDERS_CONTENT=$(cat "$ORDERS_FILE" | base64 -w 0)
    fi
fi

# 4. Construct JSON Output
# We use Python to robustly construct the JSON to avoid shell quoting hell
python3 -c "
import json
import base64
import os

def decode(b64_str):
    if not b64_str: return ''
    try:
        return base64.b64decode(b64_str).decode('utf-8', errors='ignore')
    except:
        return ''

result = {
    'task_start': $TASK_START,
    'current_time': $CURRENT_TIME,
    'scenario_exists': json.loads('$SCENARIO_EXISTS'.lower()),
    'environment_ini': decode('$ENV_CONTENT'),
    'ownship_ini': decode('$OWNSHIP_CONTENT'),
    'othership_ini': decode('$OTHERSHIP_CONTENT'),
    'bc5_ini': decode('$CONFIG_CONTENT'),
    'briefing_exists': json.loads('$BRIEFING_EXISTS'.lower()),
    'briefing_content': decode('$BRIEFING_CONTENT'),
    'orders_exists': json.loads('$ORDERS_EXISTS'.lower()),
    'orders_content': decode('$ORDERS_CONTENT'),
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"