#!/bin/bash
echo "=== Exporting collision_config_map Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/collision_config_map_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/collision_map.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/collision_report.json"

take_screenshot /tmp/collision_config_map_end_screenshot.png

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"valid_structure": false, "joints_varied_count": 0, "has_both_collision_states": false, "unique_ee_positions": 0, "ee_spread_m": 0.0}'

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
import csv, json, sys, math

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/collision_map.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"valid_structure": False, "joints_varied_count": 0, "has_both_collision_states": False, "unique_ee_positions": 0, "ee_spread_m": 0.0}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    
    # Check EE coords
    ex = find_col(headers, ['ee_x','x','ee_x_m'])
    ey = find_col(headers, ['ee_y','y','ee_y_m'])
    ez = find_col(headers, ['ee_z','z','ee_z_m'])
    
    # Check Collision column
    col_col = find_col(headers, ['collision','is_collision','collides'])
    
    # Count joint ranges > 40 degrees
    joints_varied_count = 0
    joint_cols = [c for c in headers if 'j' in c.lower() or 'q' in c.lower() or 'joint' in c.lower()]
    for jcol in joint_cols:
        try:
            vals = [float(r[jcol]) for r in rows if str(r.get(jcol,'')).strip()]
            if vals and max(vals) - min(vals) >= 40.0:
                joints_varied_count += 1
        except:
            pass
            
    has_both_collision_states = False
    if col_col:
        col_vals = [str(r.get(col_col,'')).strip().lower() for r in rows]
        has_true = any(v in ['true', '1', 'yes', 't'] for v in col_vals)
        has_false = any(v in ['false', '0', 'no', 'f'] for v in col_vals)
        has_both_collision_states = has_true and has_false
        
    unique_ee = 0
    ee_spread = 0.0
    if ex and ey and ez:
        xs = []
        ys = []
        zs = []
        pts = []
        for r in rows:
            try:
                x, y, z = float(r[ex]), float(r[ey]), float(r[ez])
                xs.append(x)
                ys.append(y)
                zs.append(z)
                # Round to 1mm to count distinct locations
                pts.append((round(x,3), round(y,3), round(z,3)))
            except:
                pass
        unique_ee = len(set(pts))
        if xs and ys and zs:
            ee_spread = max(
                max(xs)-min(xs),
                max(ys)-min(ys),
                max(zs)-min(zs)
            )
            
    valid_structure = bool(ex and ey and ez and col_col)
            
    print(json.dumps({
        "valid_structure": valid_structure,
        "joints_varied_count": joints_varied_count,
        "has_both_collision_states": has_both_collision_states,
        "unique_ee_positions": unique_ee,
        "ee_spread_m": ee_spread
    }))
except Exception as e:
    print(json.dumps({"valid_structure": False, "joints_varied_count": 0, "has_both_collision_states": False, "unique_ee_positions": 0, "ee_spread_m": 0.0, "error": str(e)}))
PYEOF
    )
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_ANALYSIS='{"valid_fields": false, "total_configs": 0, "obstacles_placed": 0, "valid_obstacle_positions": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    
    JSON_ANALYSIS=$(python3 -c "
import json, math
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_configs','collision_count','collision_free_count','collision_rate_pct','obstacles_placed','obstacle_positions']
    valid_fields = all(k in d for k in req)
    
    total = int(d.get('total_configs', 0))
    obs_placed = int(d.get('obstacles_placed', 0))
    
    # Internal consistency check
    cc = int(d.get('collision_count', -1))
    cfc = int(d.get('collision_free_count', -1))
    if cc + cfc != total:
        valid_fields = False
        
    pos = d.get('obstacle_positions', [])
    valid_pos = False
    if isinstance(pos, list) and len(pos) >= 3:
        valid_pos = True
        for p in pos:
            if not isinstance(p, list) or len(p) != 3:
                valid_pos = False
                break
        if valid_pos:
            # Check mutually >= 0.1m apart to ensure distinct distinct obstacles
            for i in range(len(pos)):
                for j in range(i+1, len(pos)):
                    dist = math.sqrt(sum((pos[i][k] - pos[j][k])**2 for k in range(3)))
                    if dist < 0.1:
                        valid_pos = False
                        break
                        
    print(json.dumps({
        'valid_fields': valid_fields,
        'total_configs': total,
        'obstacles_placed': obs_placed,
        'valid_obstacle_positions': valid_pos
    }))
except Exception as e:
    print(json.dumps({'valid_fields': False, 'total_configs': 0, 'obstacles_placed': 0, 'valid_obstacle_positions': False}))
" 2>/dev/null || echo '{"valid_fields": false, "total_configs": 0, "obstacles_placed": 0, "valid_obstacle_positions": false}')
fi

cat > /tmp/collision_config_map_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_analysis": $JSON_ANALYSIS
}
EOF

echo "=== Export Complete ==="