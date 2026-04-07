#!/bin/bash
echo "=== Exporting drone_waypoint_tracking Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/drone_waypoint_tracking_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/flight_log.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/flight_metrics.json"

# Capture final screenshot
take_screenshot /tmp/drone_waypoint_tracking_end_screenshot.png

# Check CSV
CSV_EXISTS=false
CSV_IS_NEW=false
if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true
fi

# Parse and evaluate CSV physics data
CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/flight_log.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"valid": False, "row_count": 0}))
        sys.exit(0)

    headers = list(rows[0].keys())
    # Extract columns
    dx = find_col(headers, ['drone_x', 'x', 'px'])
    dy = find_col(headers, ['drone_y', 'y', 'py'])
    dz = find_col(headers, ['drone_z', 'z', 'pz'])
    err_col = find_col(headers, ['error_distance_m', 'error_distance', 'error_m', 'error'])
    wp_col = find_col(headers, ['waypoint_id', 'target_id', 'wp_id'])
    tx = find_col(headers, ['target_x', 'tx'])
    ty = find_col(headers, ['target_y', 'ty'])
    tz = find_col(headers, ['target_z', 'tz'])

    has_coords = dx is not None and dy is not None and dz is not None
    max_step_dist = 0.0
    unique_wps = 0
    mean_error = 0.0

    if has_coords:
        drone_pts = []
        for r in rows:
            try:
                drone_pts.append((float(r[dx]), float(r[dy]), float(r[dz])))
            except:
                pass
        
        # Calculate max step-to-step distance to detect teleportation
        for i in range(1, len(drone_pts)):
            p1, p2 = drone_pts[i-1], drone_pts[i]
            dist = math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2 + (p1[2]-p2[2])**2)
            if dist > max_step_dist:
                max_step_dist = dist

    # Calculate distinct targets
    if wp_col:
        wps = set()
        for r in rows:
            if r.get(wp_col, '').strip():
                wps.add(r[wp_col])
        unique_wps = len(wps)
    elif tx and ty and tz:
        wps = set()
        for r in rows:
            try:
                wps.add((round(float(r[tx]),2), round(float(r[ty]),2), round(float(r[tz]),2)))
            except:
                pass
        unique_wps = len(wps)

    # Calculate mean error to detect dynamic lag
    if err_col:
        errs = []
        for r in rows:
            try:
                errs.append(float(r[err_col]))
            except:
                pass
        mean_error = sum(errs) / len(errs) if errs else 0.0

    print(json.dumps({
        "valid": True,
        "row_count": len(rows),
        "has_coords": bool(has_coords),
        "max_step_dist_m": max_step_dist,
        "unique_waypoints": unique_wps,
        "mean_error_m": mean_error
    }))
except Exception as e:
    print(json.dumps({"valid": False, "row_count": 0, "error": str(e)}))
PYEOF
)

# Check JSON
JSON_EXISTS=false
JSON_IS_NEW=false
if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
fi

# Parse JSON metrics
JSON_ANALYSIS=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_waypoints_reached', 'total_flight_time_s', 'max_tracking_error_m', 'mean_tracking_error_m', 'path_efficiency']
    has_fields = all(k in d for k in req)
    eff = float(d.get('path_efficiency', 0.0))
    wps = int(d.get('total_waypoints_reached', 0))
    print(json.dumps({'valid': True, 'has_fields': has_fields, 'path_efficiency': eff, 'total_waypoints': wps}))
except Exception as e:
    print(json.dumps({'valid': False, 'has_fields': False, 'error': str(e)}))
" 2>/dev/null || echo '{"valid": false}')

# Output final result JSON
cat > /tmp/drone_waypoint_tracking_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_analysis": $JSON_ANALYSIS
}
EOF

echo "=== Export Complete ==="