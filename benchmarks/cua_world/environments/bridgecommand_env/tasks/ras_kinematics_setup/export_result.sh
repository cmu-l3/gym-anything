#!/bin/bash
echo "=== Exporting RAS Kinematics Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) RAS Exercise"
OWNSHIP_INI="$SCENARIO_DIR/ownship.ini"
OTHERSHIP_INI="$SCENARIO_DIR/othership.ini"
ENV_INI="$SCENARIO_DIR/environment.ini"
CALC_FILE="/home/ga/Documents/ras_calc.txt"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize variables
SCENARIO_CREATED="false"
OWNSHIP_SPEED="0"
OTHERSHIP_START_LAT="0"
LEG1_DIST="0"
LEG1_SPEED="0"
LEG2_DIST="0"
LEG2_SPEED="0"
CALC_FILE_EXISTS="false"

# Check if scenario directory exists
if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_CREATED="true"
fi

# Parse Ownship.ini
if [ -f "$OWNSHIP_INI" ]; then
    # Extract InitialSpeed (handle format "Key=Value")
    OWNSHIP_SPEED=$(grep -i "InitialSpeed" "$OWNSHIP_INI" | cut -d'=' -f2 | tr -d '[:space:]' || echo "0")
fi

# Parse Othership.ini
if [ -f "$OTHERSHIP_INI" ]; then
    # Extract Start Lat
    OTHERSHIP_START_LAT=$(grep -i "InitialLat(1)" "$OTHERSHIP_INI" | cut -d'=' -f2 | tr -d '[:space:]' || echo "0")
    
    # Extract Leg 1 details: Leg(1,1)=Bearing,Speed,Distance
    # We use python for robust parsing of the CSV structure inside the value
    LEG_DATA=$(python3 -c "
import configparser
import sys

try:
    with open('$OTHERSHIP_INI', 'r') as f:
        content = f.read()
        
    # Simple manual parsing since INI format in BC can be weird (duplicate keys)
    lines = content.splitlines()
    l1_speed = 0
    l1_dist = 0
    l2_speed = 0
    l2_dist = 0
    
    for line in lines:
        line = line.strip()
        if line.lower().startswith('leg(1,1)='):
            # Format: Bearing,Speed,Distance
            parts = line.split('=')[1].split(',')
            if len(parts) >= 3:
                l1_speed = parts[1].strip()
                l1_dist = parts[2].strip()
        elif line.lower().startswith('leg(1,2)='):
            parts = line.split('=')[1].split(',')
            if len(parts) >= 3:
                l2_speed = parts[1].strip()
                l2_dist = parts[2].strip()
                
    print(f'{l1_speed}|{l1_dist}|{l2_speed}|{l2_dist}')
except Exception:
    print('0|0|0|0')
")
    
    LEG1_SPEED=$(echo "$LEG_DATA" | cut -d'|' -f1)
    LEG1_DIST=$(echo "$LEG_DATA" | cut -d'|' -f2)
    LEG2_SPEED=$(echo "$LEG_DATA" | cut -d'|' -f3)
    LEG2_DIST=$(echo "$LEG_DATA" | cut -d'|' -f4)
fi

# Check calculation file
if [ -f "$CALC_FILE" ]; then
    CALC_FILE_EXISTS="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scenario_created": $SCENARIO_CREATED,
    "files_exist": {
        "ownship": $([ -f "$OWNSHIP_INI" ] && echo "true" || echo "false"),
        "othership": $([ -f "$OTHERSHIP_INI" ] && echo "true" || echo "false"),
        "environment": $([ -f "$ENV_INI" ] && echo "true" || echo "false")
    },
    "ownship_speed": "$OWNSHIP_SPEED",
    "othership_start_lat": "$OTHERSHIP_START_LAT",
    "leg1": {
        "speed": "$LEG1_SPEED",
        "distance": "$LEG1_DIST"
    },
    "leg2": {
        "speed": "$LEG2_SPEED",
        "distance": "$LEG2_DIST"
    },
    "calc_file_exists": $CALC_FILE_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="