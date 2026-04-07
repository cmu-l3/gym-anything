#!/bin/bash
echo "=== Exporting ik_weld_trajectory Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/ik_weld_trajectory_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/weld_trajectory.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/weld_stats.json"

take_screenshot /tmp/ik_weld_trajectory_end_screenshot.png

# Check CSV
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_coords": false, "waypoints_reached": 0, "path_span_m": 0.0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        rows = list(csv.DictReader(f))
    print(len(rows))
except:
    print(0)
" 2>/dev/null || echo "0")

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, math, sys

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/weld_trajectory.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_coords": False, "waypoints_reached": 0, "path_span_m": 0.0}))
        sys.exit(0)
    headers = list(rows[0].keys())
    # Accept flexible column names
    ax = find_col(headers, ['actual_x','ax','achieved_x','measured_x','x_m','x'])
    ay = find_col(headers, ['actual_y','ay','achieved_y','measured_y','y_m','y'])
    az = find_col(headers, ['actual_z','az','achieved_z','measured_z','z_m','z'])
    reached_col = find_col(headers, ['reached','success','achieved'])
    has_coords = ax is not None and ay is not None and az is not None
    if has_coords:
        xs = [float(r[ax]) for r in rows if r.get(ax,'').strip()]
        ys = [float(r[ay]) for r in rows if r.get(ay,'').strip()]
        zs = [float(r[az]) for r in rows if r.get(az,'').strip()]
        # Path span in XY plane
        if xs and ys:
            x_range = max(xs) - min(xs)
            y_range = max(ys) - min(ys)
            path_span = math.sqrt(x_range**2 + y_range**2)
        else:
            path_span = 0.0
    else:
        path_span = 0.0
    # Count reached waypoints
    if reached_col:
        reached = sum(1 for r in rows
                     if str(r.get(reached_col,'')).strip().lower() in ['true','1','yes','reached'])
    else:
        reached = 0
    print(json.dumps({"has_coords": has_coords, "waypoints_reached": reached, "path_span_m": path_span}))
except Exception as e:
    print(json.dumps({"has_coords": False, "waypoints_reached": 0, "path_span_m": 0.0, "error": str(e)}))
PYEOF
    )
fi

# Check JSON
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_waypoints": 0, "reached_count": 0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_waypoints','reached_count','path_length_m']
    has_fields = all(k in d for k in req)
    print(json.dumps({'has_fields': has_fields, 'total_waypoints': int(d.get('total_waypoints',0)), 'reached_count': int(d.get('reached_count',0))}))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_waypoints': 0, 'reached_count': 0}))
" 2>/dev/null || echo '{"has_fields": false, "total_waypoints": 0, "reached_count": 0}')
fi

cat > /tmp/ik_weld_trajectory_result.json << EOF
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
