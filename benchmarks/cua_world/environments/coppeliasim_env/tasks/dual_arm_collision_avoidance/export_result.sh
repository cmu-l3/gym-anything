#!/bin/bash
echo "=== Exporting dual_arm_collision_avoidance Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/dual_arm_collision_avoidance_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/trial_logs.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/coordination_report.json"

# Take final screenshot
take_screenshot /tmp/dual_arm_collision_avoidance_end_screenshot.png

# Check if CoppeliaSim is running
APP_RUNNING=$(is_coppeliasim_running)

# Check CSV file
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ANALYSIS='{"has_cols": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/trial_logs.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_cols": False, "total_rows": 0}))
        sys.exit(0)

    headers = [h.strip().lower() for h in rows[0].keys()]
    
    def find_col(cands):
        for c in cands:
            if c in headers: return headers[headers.index(c)]
        return None

    tid_col = find_col(['trial_id', 'trial', 'id'])
    a_col = find_col(['robot_a_base_rad', 'robot_a_rad', 'a_rad', 'j1_a', 'robot_a_base'])
    b_col = find_col(['robot_b_base_rad', 'robot_b_rad', 'b_rad', 'j1_b', 'robot_b_base'])
    col_col = find_col(['collision_detected', 'collision', 'is_collision'])

    if not all([tid_col, a_col, b_col, col_col]):
        print(json.dumps({"has_cols": False, "total_rows": len(rows), "missing_cols": True}))
        sys.exit(0)

    trials = {}
    for r in rows:
        tid = str(r.get(tid_col, '')).strip()
        if not tid: continue
        if tid not in trials:
            trials[tid] = {'a_angles': [], 'b_angles': [], 'collisions': []}
        
        try: trials[tid]['a_angles'].append(float(r[a_col]))
        except: pass
        try: trials[tid]['b_angles'].append(float(r[b_col]))
        except: pass
        
        cv = str(r[col_col]).strip().lower()
        is_coll = cv in ['1', 'true', 'yes', 't', 'y']
        trials[tid]['collisions'].append(is_coll)

    parsed_trials = {}
    for tid, data in trials.items():
        a_range = max(data['a_angles']) - min(data['a_angles']) if data['a_angles'] else 0.0
        b_range = max(data['b_angles']) - min(data['b_angles']) if data['b_angles'] else 0.0
        has_collision = any(data['collisions'])
        parsed_trials[tid] = {
            'movement_a_rad': a_range,
            'movement_b_rad': b_range,
            'has_collision': has_collision,
            'row_count': len(data['collisions'])
        }

    print(json.dumps({
        "has_cols": True,
        "total_rows": len(rows),
        "trials": parsed_trials
    }))
except Exception as e:
    print(json.dumps({"has_cols": False, "total_rows": 0, "error": str(e)}))
PYEOF
    )
fi

# Check JSON report file
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_INFO='{"has_fields": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
    required = ['concurrent_trial_collision', 'coordinated_trial_collision', 'coordination_strategy']
    has_fields = all(k in data for k in required)
    
    # Safely get booleans
    def is_true(val):
        if isinstance(val, bool): return val
        if isinstance(val, str): return val.lower() in ['true', 'yes', '1']
        if isinstance(val, int): return val == 1
        return False
        
    c1 = is_true(data.get('concurrent_trial_collision', False))
    c2 = is_true(data.get('coordinated_trial_collision', True))
    
    print(json.dumps({
        'has_fields': has_fields, 
        'concurrent_trial_collision': c1,
        'coordinated_trial_collision': c2
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'error': str(e)}))
" 2>/dev/null || echo '{"has_fields": false}')
fi

# Write result JSON
cat > /tmp/dual_arm_collision_avoidance_result.json << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_info": $JSON_INFO
}
EOF

echo "=== Export Complete ==="