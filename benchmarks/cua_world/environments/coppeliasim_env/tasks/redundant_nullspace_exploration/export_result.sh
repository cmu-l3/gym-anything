#!/bin/bash
echo "=== Exporting redundant_nullspace_exploration Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/nullspace_exploration_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/nullspace_configs.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/nullspace_report.json"

take_screenshot /tmp/nullspace_exploration_end_screenshot.png

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_all_cols": false, "distinct_configs": 0, "max_tcp_variance": 999.0, "max_elbow_displacement": 0.0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    # Python script to mathematically validate the CSV dataset
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, math, sys

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/nullspace_configs.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"has_all_cols": False, "distinct_configs": 0, "max_tcp_variance": 999.0, "max_elbow_displacement": 0.0}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    
    # Identify columns
    j_cols = [find_col(headers, [f'j{i}']) for i in range(1, 8)]
    tx = find_col(headers, ['tcp_x'])
    ty = find_col(headers, ['tcp_y'])
    tz = find_col(headers, ['tcp_z'])
    ex = find_col(headers, ['elbow_x'])
    ey = find_col(headers, ['elbow_y'])
    ez = find_col(headers, ['elbow_z'])
    
    has_all_cols = all(c is not None for c in j_cols) and all(c is not None for c in [tx, ty, tz, ex, ey, ez])
    
    if has_all_cols:
        tcp_pts = [(float(r[tx]), float(r[ty]), float(r[tz])) for r in rows if r[tx].strip()]
        elb_pts = [(float(r[ex]), float(r[ey]), float(r[ez])) for r in rows if r[ex].strip()]
        j_pts = [tuple(float(r[c]) for c in j_cols) for r in rows if all(r[c].strip() for c in j_cols)]
        
        # 1. Max TCP Variance (must be extremely small, meaning same target pose)
        max_tcp_var = 0.0
        for i in range(len(tcp_pts)):
            for j in range(i+1, len(tcp_pts)):
                d = math.sqrt(sum((tcp_pts[i][k] - tcp_pts[j][k])**2 for k in range(3)))
                if d > max_tcp_var: max_tcp_var = d
                
        # 2. Max Elbow Displacement (must be large enough to prove null-space motion)
        max_elb_disp = 0.0
        for i in range(len(elb_pts)):
            for j in range(i+1, len(elb_pts)):
                d = math.sqrt(sum((elb_pts[i][k] - elb_pts[j][k])**2 for k in range(3)))
                if d > max_elb_disp: max_elb_disp = d
                
        # 3. Distinct Configurations (ensure agent didn't just print the exact same joint state 30 times)
        distinct_count = 0
        accepted = []
        for jp in j_pts:
            is_distinct = True
            for ajp in accepted:
                # Euclidean distance in joint space
                d = math.sqrt(sum((jp[k] - ajp[k])**2 for k in range(7)))
                if d < 0.05: # Threshold for considering it a distinct configuration
                    is_distinct = False
                    break
            if is_distinct:
                accepted.append(jp)
                distinct_count += 1
                
        print(json.dumps({
            "has_all_cols": True,
            "distinct_configs": distinct_count,
            "max_tcp_variance": round(max_tcp_var, 6),
            "max_elbow_displacement": round(max_elb_disp, 4)
        }))
    else:
        print(json.dumps({"has_all_cols": False, "distinct_configs": 0, "max_tcp_variance": 999.0, "max_elbow_displacement": 0.0}))
except Exception as e:
    print(json.dumps({"has_all_cols": False, "distinct_configs": 0, "max_tcp_variance": 999.0, "max_elbow_displacement": 0.0, "error": str(e)}))
PYEOF
    )
    CSV_ROW_COUNT=$(python3 -c "import json; print(json.loads('$CSV_ANALYSIS').get('distinct_configs', 0))" 2>/dev/null)
fi

# Check JSON
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
    req = ['robot_model','total_distinct_configs','tcp_variance_m','max_elbow_displacement_m']
    has_fields = all(k in d for k in req)
    print(json.dumps({'has_fields': has_fields, 'total': int(d.get('total_distinct_configs',0))}))
except Exception:
    print(json.dumps({'has_fields': False}))
" 2>/dev/null || echo '{"has_fields": false}')
fi

# Determine if CoppeliaSim was left running
APP_RUNNING=$(pgrep -f "coppeliaSim" > /dev/null && echo "true" || echo "false")

cat > /tmp/nullspace_exploration_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS,
    "app_running": $APP_RUNNING
}
EOF

echo "=== Export Complete ==="