#!/bin/bash
echo "=== Exporting conveyor_line_tracking Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/conveyor_line_tracking_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/conveyor_tracking.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/tracking_report.json"

take_screenshot /tmp/conveyor_line_tracking_end_screenshot.png

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_columns": false, "total_time_s": 0.0, "part_travel_m": 0.0, "part_moves": false, "catch_up_achieved": false, "post_catch_up_mean_error": 0.0}'

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
    with open('/home/ga/Documents/CoppeliaSim/exports/conveyor_tracking.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_columns": False, "total_time_s": 0.0, "part_travel_m": 0.0, "part_moves": False, "catch_up_achieved": False, "post_catch_up_mean_error": 0.0}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    t_col = find_col(headers, ['time_s', 'time', 't'])
    py_col = find_col(headers, ['part_y', 'py', 'y_part'])
    ty_col = find_col(headers, ['tip_y', 'ty', 'y_tip'])
    err_col = find_col(headers, ['error_mm', 'error', 'err'])
    
    has_columns = t_col is not None and py_col is not None and err_col is not None
    
    if has_columns:
        times = [float(r[t_col]) for r in rows if r.get(t_col,'').strip()]
        p_ys = [float(r[py_col]) for r in rows if r.get(py_col,'').strip()]
        errs = [float(r[err_col]) for r in rows if r.get(err_col,'').strip()]
        
        total_time = max(times) - min(times) if times else 0.0
        part_travel = abs(p_ys[-1] - p_ys[0]) if p_ys else 0.0
        
        part_moves = part_travel > 0.1
        
        catch_up_achieved = False
        post_catch_up_mean_error = 0.0
        catch_up_idx = -1
        
        for i, e in enumerate(errs):
            if e < 10.0:
                catch_up_achieved = True
                catch_up_idx = i
                break
                
        if catch_up_achieved and catch_up_idx < len(errs) - 1:
            post_errs = errs[catch_up_idx:]
            post_catch_up_mean_error = sum(post_errs) / len(post_errs)
            
        print(json.dumps({
            "has_columns": has_columns,
            "total_time_s": total_time,
            "part_travel_m": part_travel,
            "part_moves": part_moves,
            "catch_up_achieved": catch_up_achieved,
            "post_catch_up_mean_error": post_catch_up_mean_error
        }))
    else:
        print(json.dumps({"has_columns": False, "total_time_s": 0.0, "part_travel_m": 0.0, "part_moves": False, "catch_up_achieved": False, "post_catch_up_mean_error": 0.0}))
except Exception as e:
    print(json.dumps({"has_columns": False, "total_time_s": 0.0, "part_travel_m": 0.0, "part_moves": False, "catch_up_achieved": False, "post_catch_up_mean_error": 0.0, "error": str(e)}))
PYEOF
    )
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_simulation_time_s": 0.0, "catch_up_time_s": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_simulation_time_s', 'part_travel_distance_m', 'catch_up_time_s', 'mean_tracking_error_mm', 'max_tracking_error_mm']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'total_simulation_time_s': float(d.get('total_simulation_time_s', 0.0)),
        'catch_up_time_s': float(d.get('catch_up_time_s', 0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_simulation_time_s': 0.0, 'catch_up_time_s': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "total_simulation_time_s": 0.0, "catch_up_time_s": 0.0}')
fi

cat > /tmp/conveyor_line_tracking_result.json << EOF
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