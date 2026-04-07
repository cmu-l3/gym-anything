#!/bin/bash
echo "=== Exporting liquid_handling_spill_prevention Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/liquid_handling_spill_prevention_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/transport_telemetry.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/spill_report.json"

# Take final screenshot for VLM evaluation
take_screenshot /tmp/liquid_handling_spill_prevention_end_screenshot.png

# Initial checks
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_columns": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        print(len(list(csv.DictReader(f))))
except:
    print(0)
" 2>/dev/null || echo "0")

    # Perform analysis of geometry, tilt, and acceleration constraints
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, math, sys

def dist(p1, p2):
    return math.sqrt(sum((a-b)**2 for a,b in zip(p1,p2)))

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/transport_telemetry.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_columns": False}))
        sys.exit(0)
        
    headers = [h.strip().lower() for h in rows[0].keys()]
    
    def get_col(candidates):
        for h in headers:
            for c in candidates:
                if c in h: return h
        return None
        
    cx = get_col(['pos_x', 'x_m', 'x', 'px'])
    cy = get_col(['pos_y', 'y_m', 'y', 'py'])
    cz = get_col(['pos_z', 'z_m', 'z', 'pz'])
    ct = get_col(['tilt_error_deg', 'tilt', 'error'])
    ca = get_col(['accel_magnitude_ms2', 'accel'])
    
    # Required target waypoints
    wp0 = (0.4, -0.2, 0.2)
    wp1 = (0.4, -0.2, 0.5)
    wp2 = (-0.4, 0.3, 0.5)
    wp3 = (-0.4, 0.3, 0.2)
    
    min_d0 = min_d1 = min_d2 = min_d3 = 999.0
    max_tilt = 0.0
    max_accel = 0.0
    
    if cx and cy and cz:
        for r in rows:
            try:
                x, y, z = float(r[cx]), float(r[cy]), float(r[cz])
                min_d0 = min(min_d0, dist((x,y,z), wp0))
                min_d1 = min(min_d1, dist((x,y,z), wp1))
                min_d2 = min(min_d2, dist((x,y,z), wp2))
                min_d3 = min(min_d3, dist((x,y,z), wp3))
            except: pass
            
    if ct:
        for r in rows:
            try: max_tilt = max(max_tilt, float(r[ct]))
            except: pass
            
    if ca:
        for r in rows:
            try: max_accel = max(max_accel, float(r[ca]))
            except: pass

    # Must fall within 25cm radius to count as visited (allows for obstacle avoidance & singularities)
    waypoints_visited = sum(1 for d in [min_d0, min_d1, min_d2, min_d3] if d < 0.25)
    
    print(json.dumps({
        "has_columns": bool(cx and cy and cz and ct and ca),
        "waypoints_visited": waypoints_visited,
        "min_dist_wp0": min_d0,
        "min_dist_wp1": min_d1,
        "min_dist_wp2": min_d2,
        "min_dist_wp3": min_d3,
        "max_tilt": max_tilt,
        "max_accel": max_accel
    }))
except Exception as e:
    print(json.dumps({"has_columns": False, "error": str(e)}))
PYEOF
    )
fi

# Verify JSON
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    
    JSON_FIELDS=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
    req = ['total_steps_recorded', 'trajectory_completed', 'max_tilt_error_deg', 'max_accel_ms2', 'spill_prevented']
    has_fields = all(k in data for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'spill_prevented': bool(data.get('spill_prevented', False)),
        'trajectory_completed': bool(data.get('trajectory_completed', False))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'error': str(e)}))
" 2>/dev/null || echo '{"has_fields": false}')
fi

# Consolidate results for verifier
cat > /tmp/liquid_handling_spill_prevention_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS
}
EOF

echo "=== Export Complete ==="