#!/bin/bash
echo "=== Exporting UKC Passage Plan Results ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/p) Southampton Deep Draft Transit"
PLAN_FILE="/home/ga/Documents/PassagePlanning/ukc_passage_plan.txt"
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
BC_DATA_CONFIG="/opt/bridgecommand/bc5.ini"

# Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Scenario Existence & Timestamp
SCENARIO_EXISTS=false
ENV_FILE="$SCENARIO_DIR/environment.ini"
OWN_FILE="$SCENARIO_DIR/ownship.ini"
OTHER_FILE="$SCENARIO_DIR/othership.ini"

if [ -d "$SCENARIO_DIR" ] && [ -f "$ENV_FILE" ]; then
    SCENARIO_MTIME=$(stat -c %Y "$ENV_FILE" 2>/dev/null || echo "0")
    if [ "$SCENARIO_MTIME" -gt "$TASK_START" ]; then
        SCENARIO_EXISTS=true
    fi
fi

# 3. Read Scenario Values
START_TIME=""
SETTING=""
OWN_SPEED=""
OWN_LAT=""

if [ "$SCENARIO_EXISTS" = "true" ]; then
    # Parse environment.ini
    START_TIME=$(grep -i "^StartTime=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
    SETTING=$(grep -i "^Setting=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d '[:space:]')
    
    # Parse ownship.ini
    OWN_SPEED=$(grep -i "^InitialSpeed=" "$OWN_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
    OWN_LAT=$(grep -i "^InitialLat=" "$OWN_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
fi

# 4. Check Passage Plan Document
PLAN_EXISTS=false
PLAN_CONTENT=""
if [ -f "$PLAN_FILE" ]; then
    PLAN_MTIME=$(stat -c %Y "$PLAN_FILE" 2>/dev/null || echo "0")
    if [ "$PLAN_MTIME" -gt "$TASK_START" ]; then
        PLAN_EXISTS=true
        # Read first 3000 chars of plan for analysis
        PLAN_CONTENT=$(head -c 3000 "$PLAN_FILE")
    fi
fi

# 5. Check Radar Configuration (Check both config locations)
FULL_RADAR=""
MAX_RANGE=""
RANGE_RES=""

for cfg in "$BC_CONFIG" "$BC_DATA_CONFIG"; do
    if [ -f "$cfg" ]; then
        val=$(grep -i "^full_radar=" "$cfg" | cut -d'=' -f2 | tr -d '[:space:]')
        [ -n "$val" ] && FULL_RADAR="$val"
        
        val=$(grep -i "^max_radar_range=" "$cfg" | cut -d'=' -f2 | tr -d '[:space:]')
        [ -n "$val" ] && MAX_RANGE="$val"
        
        val=$(grep -i "^radar_range_resolution=" "$cfg" | cut -d'=' -f2 | tr -d '[:space:]')
        [ -n "$val" ] && RANGE_RES="$val"
    fi
done

# 6. Generate JSON Result
# Use python to safely escape content
python3 -c "
import json
import os

result = {
    'scenario_exists': $SCENARIO_EXISTS,
    'plan_exists': $PLAN_EXISTS,
    'start_time': '$START_TIME',
    'setting': '$SETTING',
    'own_speed': '$OWN_SPEED',
    'own_lat': '$OWN_LAT',
    'radar_config': {
        'full_radar': '$FULL_RADAR',
        'max_range': '$MAX_RANGE',
        'range_res': '$RANGE_RES'
    },
    'plan_content': '''$PLAN_CONTENT''',
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete."