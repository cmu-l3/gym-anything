#!/bin/bash
echo "=== Exporting restricted_vis_emergency_drill Result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/m) Portsmouth Approach Custom"
BC_CONFIG="/home/ga/.config/Bridge Command/bc5.ini"
CHECKLIST_FILE="/home/ga/Documents/fog_drill_checklist.txt"

su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# Parse environment.ini
VIS_RANGE=""
WEATHER=""
RAIN=""
START_TIME=""
if [ -f "$SCENARIO_DIR/environment.ini" ]; then
    VIS_RANGE=$(grep -oP 'VisibilityRange=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    WEATHER=$(grep -oP 'Weather=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    RAIN=$(grep -oP 'Rain=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
    START_TIME=$(grep -oP 'StartTime=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
fi

# Parse ownship.ini
OWN_NAME=""
OWN_SPEED=""
if [ -f "$SCENARIO_DIR/ownship.ini" ]; then
    OWN_NAME=$(grep -oP 'ShipName="\K[^"]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || grep -oP 'ShipName=\K.*' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
    OWN_SPEED=$(grep -oP 'InitialSpeed=\K[0-9.]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
fi

# Parse othership.ini — vessel count, types, speeds
VESSEL_COUNT=0
ALL_SPEEDS=""
VESSEL_TYPES=""
THIRD_VESSEL_TYPE=""
if [ -f "$SCENARIO_DIR/othership.ini" ]; then
    VESSEL_COUNT=$(grep -oP 'Number=\K[0-9]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "0")
    ALL_SPEEDS=$(grep -oP 'Speed\([0-9]+,[0-9]+\)=\K[0-9.]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    VESSEL_TYPES=$(grep -oP 'Type\([0-9]+\)="\K[^"]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    # Get third vessel type if it exists
    THIRD_VESSEL_TYPE=$(grep -oP 'Type\(3\)="\K[^"]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "")
    # Get vessel 1 first leg speed
    V1_SPEED=$(grep -oP 'Speed\(1,1\)=\K[0-9.]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "")
    V2_SPEED=$(grep -oP 'Speed\(2,1\)=\K[0-9.]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "")
fi

# Check radar config
FULL_RADAR=""
ARPA_ON=""
RADAR_RES=""
MAX_RANGE=""
for cfg in "$BC_CONFIG" "$BC_DATA/bc5.ini" "/home/ga/.Bridge Command/5.10/bc5.ini"; do
    if [ -f "$cfg" ]; then
        val=$(grep -oP 'full_radar=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'full_radar="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && FULL_RADAR="$val"
        val=$(grep -oP 'arpa_on=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'arpa_on="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && ARPA_ON="$val"
        val=$(grep -oP 'radar_range_resolution=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'radar_range_resolution="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && RADAR_RES="$val"
        val=$(grep -oP 'max_radar_range=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'max_radar_range="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && MAX_RANGE="$val"
    fi
done

# Check checklist
CHECKLIST_EXISTS="false"
CHECKLIST_LINE_COUNT=0
if [ -f "$CHECKLIST_FILE" ]; then
    CHECKLIST_EXISTS="true"
    CHECKLIST_LINE_COUNT=$(wc -l < "$CHECKLIST_FILE" 2>/dev/null || echo "0")
fi

# Count numbered items in checklist
NUMBERED_ITEMS=0
if [ "$CHECKLIST_EXISTS" = "true" ]; then
    NUMBERED_ITEMS=$(grep -cP '^\s*\d+[\.\)]\s' "$CHECKLIST_FILE" 2>/dev/null || echo "0")
fi

# Build result JSON
python3 -c "
import json

checklist_content = ''
if '$CHECKLIST_EXISTS' == 'true':
    try:
        with open('$CHECKLIST_FILE', 'r') as f:
            checklist_content = f.read()[:5000]
    except:
        pass

result = {
    'task': 'restricted_vis_emergency_drill',
    'environment': {
        'visibility_range': '${VIS_RANGE}',
        'weather': '${WEATHER}',
        'rain': '${RAIN}',
        'start_time': '${START_TIME}'
    },
    'ownship': {
        'name': '${OWN_NAME}',
        'speed': '${OWN_SPEED}'
    },
    'othership': {
        'vessel_count': int('${VESSEL_COUNT}' or '0'),
        'vessel_types': '${VESSEL_TYPES}',
        'third_vessel_type': '${THIRD_VESSEL_TYPE}',
        'all_speeds': '${ALL_SPEEDS}',
        'v1_speed': '${V1_SPEED}',
        'v2_speed': '${V2_SPEED}'
    },
    'radar_config': {
        'full_radar': '${FULL_RADAR}',
        'arpa_on': '${ARPA_ON}',
        'radar_range_resolution': '${RADAR_RES}',
        'max_radar_range': '${MAX_RANGE}'
    },
    'checklist': {
        'exists': $( [ \"$CHECKLIST_EXISTS\" = \"true\" ] && echo 'True' || echo 'False'),
        'line_count': $CHECKLIST_LINE_COUNT,
        'numbered_items': $NUMBERED_ITEMS,
        'content': checklist_content
    }
}

with open('/tmp/restricted_vis_emergency_drill_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2)[:2000])
"

echo "=== Export Complete ==="
