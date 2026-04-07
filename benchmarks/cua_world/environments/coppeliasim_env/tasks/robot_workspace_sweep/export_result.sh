#!/bin/bash
echo "=== Exporting robot_workspace_sweep Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/robot_workspace_sweep_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/workspace_samples.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/workspace_report.json"

# Take final screenshot
take_screenshot /tmp/robot_workspace_sweep_end_screenshot.png

# Check CSV file
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_HAS_XYZ=false
CSV_REACH_RANGE=0.0

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    # Count data rows (exclude header)
    CSV_ROW_COUNT=$(python3 -c "
import csv, sys
try:
    with open('$CSV') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    print(len(rows))
except:
    print(0)
" 2>/dev/null || echo "0")

    # Check if x_m, y_m, z_m columns exist and have non-trivial range
    CSV_STATS=$(python3 << 'PYEOF'
import csv, sys, json, math
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/workspace_samples.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_xyz": False, "reach_range": 0.0, "unique_positions": 0}))
        sys.exit(0)
    # Try to find x,y,z columns (flexible naming)
    xcol = next((k for k in rows[0] if k.strip().lower() in ['x_m','x','px','pos_x']), None)
    ycol = next((k for k in rows[0] if k.strip().lower() in ['y_m','y','py','pos_y']), None)
    zcol = next((k for k in rows[0] if k.strip().lower() in ['z_m','z','pz','pos_z']), None)
    rcol = next((k for k in rows[0] if 'reach' in k.lower() or 'radius' in k.lower()), None)
    has_xyz = xcol is not None and ycol is not None and zcol is not None
    if has_xyz:
        xs = [float(r[xcol]) for r in rows if r[xcol].strip()]
        ys = [float(r[ycol]) for r in rows if r[ycol].strip()]
        zs = [float(r[zcol]) for r in rows if r[zcol].strip()]
        # Reach radii
        if rcol:
            rs = [float(r[rcol]) for r in rows if r.get(rcol,'').strip()]
        else:
            rs = [math.sqrt(x**2 + y**2 + z**2) for x,y,z in zip(xs,ys,zs)]
        reach_range = max(rs) - min(rs) if rs else 0.0
        # Count unique rounded positions (0.1m grid)
        pos_set = set()
        for x,y,z in zip(xs,ys,zs):
            pos_set.add((round(x,1), round(y,1), round(z,1)))
        unique_pos = len(pos_set)
    else:
        reach_range = 0.0
        unique_pos = 0
    print(json.dumps({"has_xyz": has_xyz, "reach_range": reach_range, "unique_positions": unique_pos}))
except Exception as e:
    print(json.dumps({"has_xyz": False, "reach_range": 0.0, "unique_positions": 0, "error": str(e)}))
PYEOF
    )
fi

# Check JSON report file
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_HAS_FIELDS=false
JSON_MAX_REACH=0.0

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
    required = ['total_samples','max_reach_m','min_reach_m']
    has_fields = all(k in data for k in required)
    max_reach = float(data.get('max_reach_m', 0))
    total = int(data.get('total_samples', 0))
    print(json.dumps({'has_fields': has_fields, 'max_reach': max_reach, 'total_samples': total}))
except Exception as e:
    print(json.dumps({'has_fields': False, 'max_reach': 0.0, 'total_samples': 0}))
" 2>/dev/null || echo '{"has_fields": false, "max_reach": 0.0, "total_samples": 0}')
fi

# Write result JSON
cat > /tmp/robot_workspace_sweep_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_stats": $CSV_STATS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_info": ${JSON_INFO:-{"has_fields": false, "max_reach": 0.0, "total_samples": 0}}
}
EOF

echo "=== Export Complete ==="
