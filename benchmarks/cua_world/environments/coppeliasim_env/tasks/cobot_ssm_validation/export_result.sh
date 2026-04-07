#!/bin/bash
set -euo pipefail

echo "=== Exporting cobot_ssm_validation Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/cobot_ssm_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/ssm_telemetry.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/ssm_summary.json"

# Take final screenshot
take_screenshot /tmp/cobot_ssm_end_screenshot.png

# ---------------------------------------------------------
# Validate and Parse CSV Telemetry
# ---------------------------------------------------------
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ANALYSIS='{"has_rows": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW=true
    fi

    # Run Python inline script to deeply analyze the trajectory CSV
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/ssm_telemetry.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_rows": False}))
        sys.exit(0)

    headers = list(rows[0].keys())
    req_cols = ['time_s', 'distance_m', 'active_zone', 'robot_speed']
    has_cols = all(any(c in h.lower() for h in headers) for c in req_cols)

    def get_col(candidates):
        for h in headers:
            if any(c in h.lower() for c in candidates): return h
        return None

    d_col = get_col(['distance'])
    z_col = get_col(['zone', 'active'])
    s_col = get_col(['speed', 'velocity'])

    start_dist = float(rows[0][d_col]) if d_col and rows[0][d_col].strip() else 0.0
    end_dist = float(rows[-1][d_col]) if d_col and rows[-1][d_col].strip() else 0.0

    zone_logic_correct = True
    green_speeds, yellow_speeds, red_speeds = [], [], []

    for r in rows:
        if not d_col or not z_col or not s_col:
            break
        try:
            d = float(r[d_col])
            z = str(r[z_col]).strip().upper()
            s = abs(float(r[s_col]))

            # Tolerances for float boundary transitions (+/- 0.05m)
            if 'GREEN' in z and d < 0.95: zone_logic_correct = False
            if 'YELLOW' in z and (d > 1.05 or d < 0.45): zone_logic_correct = False
            if 'RED' in z and d > 0.55: zone_logic_correct = False

            if 'GREEN' in z: green_speeds.append(s)
            elif 'YELLOW' in z: yellow_speeds.append(s)
            elif 'RED' in z: red_speeds.append(s)
        except:
            pass

    mean_green = sum(green_speeds)/len(green_speeds) if green_speeds else 0.0
    mean_yellow = sum(yellow_speeds)/len(yellow_speeds) if yellow_speeds else 0.0
    max_red = max(red_speeds) if red_speeds else 0.0

    print(json.dumps({
        "has_rows": True,
        "has_cols": has_cols,
        "start_distance": start_dist,
        "end_distance": end_dist,
        "zone_logic_correct": zone_logic_correct,
        "mean_green_speed": mean_green,
        "mean_yellow_speed": mean_yellow,
        "max_red_speed": max_red,
        "has_red": len(red_speeds) > 0,
        "has_green": len(green_speeds) > 0,
        "has_yellow": len(yellow_speeds) > 0
    }))
except Exception as e:
    print(json.dumps({"has_rows": False, "error": str(e)}))
PYEOF
    )
fi

# ---------------------------------------------------------
# Validate and Parse JSON Summary
# ---------------------------------------------------------
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "successful_stop": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW=true
    fi

    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_steps', 'start_distance_m', 'min_distance_m', 'green_steps', 'yellow_steps', 'red_steps', 'successful_stop']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'successful_stop': bool(d.get('successful_stop', False))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'successful_stop': False}))
" 2>/dev/null || echo '{"has_fields": false, "successful_stop": false}')
fi

# ---------------------------------------------------------
# Compile final payload
# ---------------------------------------------------------
cat > /tmp/cobot_ssm_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS
}
EOF

echo "=== Export Complete ==="