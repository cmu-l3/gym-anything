#!/bin/bash
echo "=== Exporting obstacle_path_planning Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts.txt 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/obstacle_path.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/path_planning_report.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check CSV file properties
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_coords": false, "path_length_m": 0.0, "collision_free_pct": 0.0, "start_goal_dist": 0.0, "valid_clearance": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, math, sys

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/obstacle_path.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_coords": False, "path_length_m": 0.0, "collision_free_pct": 0.0, "start_goal_dist": 0.0, "valid_clearance": False, "row_count": 0}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    ax = find_col(headers, ['actual_x', 'x'])
    ay = find_col(headers, ['actual_y', 'y'])
    az = find_col(headers, ['actual_z', 'z'])
    cf = find_col(headers, ['collision_free', 'free', 'safe'])
    cl = find_col(headers, ['min_clearance_m', 'clearance_m', 'clearance'])

    has_coords = bool(ax and ay and az)
    path_len = 0.0
    start_goal_dist = 0.0
    cf_pct = 0.0
    valid_clearance = False

    if has_coords:
        pts = []
        for r in rows:
            try:
                pts.append((float(r[ax]), float(r[ay]), float(r[az])))
            except:
                pass
        
        for i in range(1, len(pts)):
            dx = pts[i][0] - pts[i-1][0]
            dy = pts[i][1] - pts[i-1][1]
            dz = pts[i][2] - pts[i-1][2]
            path_len += math.sqrt(dx*dx + dy*dy + dz*dz)
            
        if len(pts) > 1:
            dx = pts[-1][0] - pts[0][0]
            dy = pts[-1][1] - pts[0][1]
            dz = pts[-1][2] - pts[0][2]
            start_goal_dist = math.sqrt(dx*dx + dy*dy + dz*dz)

    if cf:
        safe_count = sum(1 for r in rows if str(r.get(cf, '')).strip() in ['1', 'true', 'True'])
        cf_pct = safe_count / len(rows) if rows else 0.0

    if cl:
        clearances = [float(r[cl]) for r in rows if str(r.get(cl, '')).strip() != '']
        if clearances and max(clearances) > 0:
            valid_clearance = True

    print(json.dumps({
        "has_coords": has_coords,
        "path_length_m": path_len,
        "collision_free_pct": cf_pct,
        "start_goal_dist": start_goal_dist,
        "valid_clearance": valid_clearance,
        "row_count": len(rows)
    }))
except Exception as e:
    print(json.dumps({"has_coords": False, "path_length_m": 0.0, "collision_free_pct": 0.0, "start_goal_dist": 0.0, "valid_clearance": False, "row_count": 0, "error": str(e)}))
PYEOF
    )
    CSV_ROW_COUNT=$(echo "$CSV_ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('row_count', 0))")
fi

# Check JSON file properties
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_waypoints": 0, "path_success": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_waypoints', 'collision_free_count', 'total_path_length_m', 'min_clearance_m', 'obstacle_count', 'start_xyz', 'goal_xyz', 'path_success']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'total_waypoints': int(d.get('total_waypoints', 0)),
        'path_success': bool(d.get('path_success', False))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_waypoints': 0, 'path_success': False}))
" 2>/dev/null || echo '{"has_fields": false, "total_waypoints": 0, "path_success": false}')
fi

# Determine if app was running
APP_RUNNING=$(pgrep -f "coppeliaSim" > /dev/null && echo "true" || echo "false")

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
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