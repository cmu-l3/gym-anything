#!/bin/bash
echo "=== Exporting dual_robot_interlock Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/dual_robot_interlock_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/interlock_telemetry.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/interlock_report.json"

# Take final screenshot
take_screenshot /tmp/dual_robot_interlock_end_screenshot.png

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ANALYSIS='{"valid": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    # Run Python script to parse CSV and validate kinematics and cycles
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

def dist(p1, p2):
    return math.sqrt(sum((a-b)**2 for a,b in zip(p1,p2)))

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/interlock_telemetry.csv', 'r') as f:
        rows = list(csv.DictReader(f))

    if not rows:
        print(json.dumps({"valid": False, "error": "Empty CSV"}))
        sys.exit(0)

    headers = list(rows[0].keys())
    
    # Flexible column matching
    r1x = find_col(headers, ['r1_ee_x', 'r1_x'])
    r1y = find_col(headers, ['r1_ee_y', 'r1_y'])
    r1z = find_col(headers, ['r1_ee_z', 'r1_z'])
    
    r2x = find_col(headers, ['r2_ee_x', 'r2_x'])
    r2y = find_col(headers, ['r2_ee_y', 'r2_y'])
    r2z = find_col(headers, ['r2_ee_z', 'r2_z'])

    if not all([r1x, r1y, r1z, r2x, r2y, r2z]):
        print(json.dumps({"valid": False, "error": "Missing EE coordinate columns"}))
        sys.exit(0)

    r1_cycles = 0
    r2_cycles = 0
    r1_state = 0 # 0 = Home, 1 = Zone
    r2_state = 0 

    max_step_dist = 0.0
    min_ee_dist = 999.0
    simultaneous_violations = 0
    valid_rows = 0

    prev_r1 = None
    prev_r2 = None

    center = (0.0, 0.0, 0.5)

    for row in rows:
        try:
            p1 = (float(row[r1x]), float(row[r1y]), float(row[r1z]))
            p2 = (float(row[r2x]), float(row[r2y]), float(row[r2z]))
            valid_rows += 1

            ee_dist = dist(p1, p2)
            if ee_dist < min_ee_dist: min_ee_dist = ee_dist

            if prev_r1 and prev_r2:
                d1_step = dist(p1, prev_r1)
                d2_step = dist(p2, prev_r2)
                max_step_dist = max(max_step_dist, d1_step, d2_step)

            d1_center = dist(p1, center)
            d2_center = dist(p2, center)

            r1_in = d1_center <= 0.3
            r2_in = d2_center <= 0.3

            if r1_in and r2_in:
                simultaneous_violations += 1

            # R1 Cycle State Machine
            if r1_state == 0 and r1_in:
                r1_state = 1
            elif r1_state == 1 and d1_center > 0.6:
                r1_state = 0
                r1_cycles += 1

            # R2 Cycle State Machine
            if r2_state == 0 and r2_in:
                r2_state = 1
            elif r2_state == 1 and d2_center > 0.6:
                r2_state = 0
                r2_cycles += 1

            prev_r1 = p1
            prev_r2 = p2
        except ValueError:
            pass # Skip rows with bad float conversions

    print(json.dumps({
        "valid": True,
        "row_count": valid_rows,
        "r1_cycles": r1_cycles,
        "r2_cycles": r2_cycles,
        "min_ee_dist": min_ee_dist if min_ee_dist != 999.0 else 0.0,
        "max_step_dist": max_step_dist,
        "simultaneous_violations": simultaneous_violations
    }))

except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_sim_time_s', 'r1_cycles_completed', 'r2_cycles_completed', 'min_ee_distance_m', 'simultaneous_zone_violations']
    has_fields = all(k in d for k in req)
    print(json.dumps({'has_fields': has_fields, 'reported_min_dist': float(d.get('min_ee_distance_m', 0))}))
except Exception:
    print(json.dumps({'has_fields': False}))
" 2>/dev/null || echo '{"has_fields": false}')
fi

# Write summary to a single result file for the verifier
cat > /tmp/dual_robot_interlock_result.json << EOF
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