#!/bin/bash
echo "=== Exporting agv_incline_torque_sizing Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/agv_incline_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/incline_profiling.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/motor_sizing_report.json"

take_screenshot /tmp/agv_incline_end_screenshot.png

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_cols": false, "physics_passed": false, "max_torque_all": 0.0, "min_inc_torque": 0.0, "max_inc_torque": 0.0}'

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
    with open('/home/ga/Documents/CoppeliaSim/exports/incline_profiling.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"has_cols": False, "physics_passed": False, "max_torque_all": 0.0}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    # Flexible column matching
    inc_col = find_col(headers, ['incline_deg','incline','angle_deg','angle','slope'])
    tl_col = find_col(headers, ['peak_torque_left_nm','torque_left','left_torque','t_left','peak_torque_left'])
    tr_col = find_col(headers, ['peak_torque_right_nm','torque_right','right_torque','t_right','peak_torque_right'])
    
    has_cols = inc_col is not None and tl_col is not None and tr_col is not None
    
    physics_passed = False
    max_torque_all = 0.0
    min_inc_torque = 0.0
    max_inc_torque = 0.0
    
    if has_cols:
        data = []
        for r in rows:
            try:
                inc = float(r[inc_col])
                # Use absolute torque magnitudes (depending on joint definitions, effort could be negative)
                tl = abs(float(r[tl_col]))
                tr = abs(float(r[tr_col]))
                data.append((inc, tl, tr))
            except:
                pass
                
        if len(data) >= 2:
            data.sort(key=lambda x: x[0])  # sort by incline
            
            # Extract torque stats
            max_torque_all = max([max(d[1], d[2]) for d in data])
            
            min_data = data[0]
            max_data = data[-1]
            
            # Avg effort across wheels for min and max inclines
            min_inc_torque = (min_data[1] + min_data[2]) / 2.0
            max_inc_torque = (max_data[1] + max_data[2]) / 2.0
            
            # Physics law check: steeper incline should require strictly more torque than flat/lowest
            if max_data[0] > min_data[0] and max_inc_torque > min_inc_torque:
                physics_passed = True

    print(json.dumps({
        "has_cols": has_cols,
        "physics_passed": physics_passed,
        "max_torque_all": max_torque_all,
        "min_inc_torque": min_inc_torque,
        "max_inc_torque": max_inc_torque
    }))
except Exception as e:
    print(json.dumps({"has_cols": False, "physics_passed": False, "max_torque_all": 0.0, "error": str(e)}))
PYEOF
    )
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "angles_tested": 0, "max_torque_observed_nm": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['robot_model_used', 'angles_tested', 'max_torque_observed_nm', 'steepest_incline_deg']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'angles_tested': int(d.get('angles_tested', 0)),
        'max_torque_observed_nm': float(d.get('max_torque_observed_nm', 0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'angles_tested': 0, 'max_torque_observed_nm': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "angles_tested": 0, "max_torque_observed_nm": 0.0}')
fi

cat > /tmp/agv_incline_result.json << EOF
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