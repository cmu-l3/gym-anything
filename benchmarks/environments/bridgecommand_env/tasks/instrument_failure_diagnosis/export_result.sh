#!/bin/bash
echo "=== Exporting instrument_failure_diagnosis Result ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/m) Portsmouth Approach Custom"
REPORT_FILE="/home/ga/Documents/fault_report.txt"

# Take final screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_final.png" 2>/dev/null || true

# Read current bc5.ini values from all possible locations
# BC may save to different locations depending on how the agent edited
VIEW_ANGLE=""
RADAR_RES=""
MAX_RANGE=""

for cfg in "/home/ga/.config/Bridge Command/bc5.ini" "$BC_DATA/bc5.ini" "/home/ga/.Bridge Command/5.10/bc5.ini"; do
    if [ -f "$cfg" ]; then
        # Try unquoted format first, then quoted
        val=$(grep -oP 'view_angle=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'view_angle="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && VIEW_ANGLE="$val"
        val=$(grep -oP 'radar_range_resolution=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'radar_range_resolution="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && RADAR_RES="$val"
        val=$(grep -oP 'max_radar_range=\K[0-9]+' "$cfg" 2>/dev/null || grep -oP 'max_radar_range="\K[^"]+' "$cfg" 2>/dev/null)
        [ -n "$val" ] && MAX_RANGE="$val"
    fi
done

# Read scenario values
VIS_RANGE=""
OWN_SPEED=""
VESSEL_COUNT=""

if [ -f "$SCENARIO_DIR/environment.ini" ]; then
    VIS_RANGE=$(grep -oP 'VisibilityRange=\K[0-9.]+' "$SCENARIO_DIR/environment.ini" 2>/dev/null || echo "")
fi

if [ -f "$SCENARIO_DIR/ownship.ini" ]; then
    OWN_SPEED=$(grep -oP 'InitialSpeed=\K[0-9.]+' "$SCENARIO_DIR/ownship.ini" 2>/dev/null || echo "")
fi

if [ -f "$SCENARIO_DIR/othership.ini" ]; then
    VESSEL_COUNT=$(grep -oP 'Number=\K[0-9]+' "$SCENARIO_DIR/othership.ini" 2>/dev/null || echo "0")
fi

# Read fault report
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_LINE_COUNT=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | head -300)
    REPORT_LINE_COUNT=$(wc -l < "$REPORT_FILE" 2>/dev/null || echo "0")
fi

# Build result JSON
python3 << 'PYEOF'
import json

result = {
    "task": "instrument_failure_diagnosis",
    "bc5_values": {
        "view_angle": VIEW_ANGLE,
        "radar_range_resolution": RADAR_RES,
        "max_radar_range": MAX_RANGE
    },
    "scenario_values": {
        "visibility_range": VIS_RANGE,
        "initial_speed": OWN_SPEED,
        "vessel_count": VESSEL_COUNT
    },
    "report": {
        "exists": REPORT_EXISTS,
        "line_count": REPORT_LINE_COUNT,
        "content": REPORT_CONTENT
    }
}

# Replace shell variables
import os, subprocess

def shell_val(var_name, default=""):
    try:
        r = subprocess.run(f'echo "${var_name}"', shell=True, capture_output=True, text=True)
        return r.stdout.strip() or default
    except:
        return default

PYEOF

# Use a simpler approach — direct JSON construction
python3 -c "
import json, os

# Read values from environment
view_angle = '${VIEW_ANGLE}'
radar_res = '${RADAR_RES}'
max_range = '${MAX_RANGE}'
vis_range = '${VIS_RANGE}'
own_speed = '${OWN_SPEED}'
vessel_count = '${VESSEL_COUNT}'
report_exists = '${REPORT_EXISTS}' == 'true'
report_line_count = int('${REPORT_LINE_COUNT}' or '0')

# Read report content safely
report_content = ''
if report_exists:
    try:
        with open('${REPORT_FILE}', 'r') as f:
            report_content = f.read()[:5000]
    except:
        pass

result = {
    'task': 'instrument_failure_diagnosis',
    'bc5_values': {
        'view_angle': view_angle,
        'radar_range_resolution': radar_res,
        'max_radar_range': max_range
    },
    'scenario_values': {
        'visibility_range': vis_range,
        'initial_speed': own_speed,
        'vessel_count': vessel_count
    },
    'report': {
        'exists': report_exists,
        'line_count': report_line_count,
        'content': report_content
    }
}

with open('/tmp/instrument_failure_diagnosis_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2)[:2000])
"

echo "=== Export Complete ==="
