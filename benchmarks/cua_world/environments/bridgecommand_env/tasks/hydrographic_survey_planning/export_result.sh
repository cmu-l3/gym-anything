#!/bin/bash
echo "=== Exporting Hydrographic Survey Result ==="

SCENARIO_DIR="/opt/bridgecommand/Scenarios/Hydrographic_Survey"
ENV_FILE="$SCENARIO_DIR/environment.ini"
OTHER_FILE="$SCENARIO_DIR/othership.ini"

# Timestamp check
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=0

if [ -f "$OTHER_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$OTHER_FILE" 2>/dev/null || echo "0")
fi

CREATED_DURING_TASK="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to read ini values
get_ini_val() {
    local file="$1"
    local key="$2"
    grep -i "^$key=" "$file" | cut -d'=' -f2 | tr -d '"' | tr -d ' ' | head -1
}

# Parse environment.ini basic info
WORLD_SETTING=""
if [ -f "$ENV_FILE" ]; then
    WORLD_SETTING=$(get_ini_val "$ENV_FILE" "Setting")
fi

# We need to parse othership.ini complex structure (indexed keys)
# We will use Python for this to get a structured JSON of the waypoints
# Bridge Command othership.ini format:
# Type(1)="Name"
# InitLat(1)=...
# Lat(1,1)=...
# Long(1,1)=...

PYTHON_PARSER=$(cat << 'PY_EOF'
import sys
import json
import re

file_path = sys.argv[1]
vessels = {}

try:
    with open(file_path, 'r') as f:
        lines = f.readlines()

    for line in lines:
        line = line.strip()
        if not line or line.startswith(';'):
            continue
        
        # Parse key=value
        if '=' not in line:
            continue
        
        key, val = line.split('=', 1)
        key = key.strip().lower()
        val = val.strip().strip('"')

        # Regex for indexed keys: key(index) or key(vessel_idx, leg_idx)
        # e.g. initlat(1) or lat(1,1)
        
        # Check for vessel properties: InitLat(1)
        m_prop = re.match(r'([a-z]+)\((\d+)\)', key)
        if m_prop:
            prop = m_prop.group(1)
            idx = int(m_prop.group(2))
            if idx not in vessels:
                vessels[idx] = {'legs': []}
            
            if prop == 'initlat': vessels[idx]['start_lat'] = float(val)
            elif prop == 'initlong': vessels[idx]['start_long'] = float(val)
            elif prop == 'initbearing': vessels[idx]['start_bearing'] = float(val)
            elif prop == 'initspeed': vessels[idx]['speed'] = float(val)
            elif prop == 'type': vessels[idx]['name'] = val
            elif prop == 'legs': vessels[idx]['leg_count'] = int(val)
            continue

        # Check for leg waypoints: Lat(1,1)
        m_leg = re.match(r'([a-z]+)\((\d+),(\d+)\)', key)
        if m_leg:
            prop = m_leg.group(1)
            v_idx = int(m_leg.group(2))
            l_idx = int(m_leg.group(3))
            
            if v_idx not in vessels:
                vessels[v_idx] = {'legs': []}
            
            # Ensure leg list is long enough
            while len(vessels[v_idx]['legs']) < l_idx:
                vessels[v_idx]['legs'].append({})
            
            leg = vessels[v_idx]['legs'][l_idx-1]
            if prop == 'lat': leg['lat'] = float(val)
            elif prop == 'long': leg['long'] = float(val)

    print(json.dumps(vessels))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PY_EOF
)

VESSEL_DATA="{}"
if [ -f "$OTHER_FILE" ]; then
    VESSEL_DATA=$(python3 -c "$PYTHON_PARSER" "$OTHER_FILE")
fi

# Load Truth Data
TRUTH_DATA="{}"
if [ -f "/tmp/survey_truth.json" ]; then
    TRUTH_DATA=$(cat /tmp/survey_truth.json)
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "scenario_created": $([ -d "$SCENARIO_DIR" ] && echo "true" || echo "false"),
    "env_file_exists": $([ -f "$ENV_FILE" ] && echo "true" || echo "false"),
    "other_file_exists": $([ -f "$OTHER_FILE" ] && echo "true" || echo "false"),
    "created_during_task": $CREATED_DURING_TASK,
    "world_setting": "$WORLD_SETTING",
    "vessel_data": $VESSEL_DATA,
    "truth_data": $TRUTH_DATA,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to safe location
cp /tmp/task_result.json /tmp/hydro_result.json
chmod 666 /tmp/hydro_result.json

echo "Result exported to /tmp/hydro_result.json"