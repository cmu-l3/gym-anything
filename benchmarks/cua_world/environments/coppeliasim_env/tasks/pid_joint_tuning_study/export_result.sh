#!/bin/bash
echo "=== Exporting pid_joint_tuning_study Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/pid_tuning_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/pid_tuning_data.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/pid_tuning_report.json"

# Take final screenshot
take_screenshot /tmp/pid_tuning_end_screenshot.png

# Check CSV file
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_columns": false, "valid_metric_rows": 0, "kp_range": 0.0, "distinct_overshoots": 0, "trials": {}}'

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
import csv, json, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/pid_tuning_data.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_columns": False, "valid_metric_rows": 0, "kp_range": 0.0, "distinct_overshoots": 0, "trials": {}}))
        sys.exit(0)
    
    orig_keys = list(rows[0].keys())
    clean_keys = [k.strip().lower() for k in orig_keys]
    req_cols = ['trial_id', 'kp', 'ki', 'kd', 'overshoot_pct', 'settling_time_s', 'rise_time_s', 'steady_state_error_deg']
    has_columns = all(c in clean_keys for c in req_cols)
    
    valid_metric_rows = 0
    kps = []
    overshoots = set()
    trials = {}
    
    if has_columns:
        def get_val(r, name):
            return r[orig_keys[clean_keys.index(name)]]
            
        for r in rows:
            try:
                tid = str(get_val(r, 'trial_id')).strip()
                kp = float(get_val(r, 'kp'))
                ki = float(get_val(r, 'ki'))
                kd = float(get_val(r, 'kd'))
                osht = float(get_val(r, 'overshoot_pct'))
                st = float(get_val(r, 'settling_time_s'))
                rt = float(get_val(r, 'rise_time_s'))
                sse = float(get_val(r, 'steady_state_error_deg'))
                
                kps.append(kp)
                overshoots.add(round(osht, 2))
                trials[tid] = {'kp': kp, 'ki': ki, 'kd': kd}
                
                if osht >= 0 and st > 0 and rt > 0 and sse >= 0:
                    valid_metric_rows += 1
            except Exception:
                pass
                
    kp_range = max(kps) - min(kps) if kps else 0.0
    print(json.dumps({
        "has_columns": has_columns,
        "valid_metric_rows": valid_metric_rows,
        "kp_range": kp_range,
        "distinct_overshoots": len(overshoots),
        "trials": trials
    }))
except Exception as e:
    print(json.dumps({"has_columns": False, "valid_metric_rows": 0, "kp_range": 0.0, "distinct_overshoots": 0, "trials": {}, "error": str(e)}))
PYEOF
    )
fi

# Check JSON report file
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_INFO='{"has_fields": false, "total_trials": 0, "step_size_deg": 0.0, "best_trial_id": "", "best_kp": -1.0, "best_ki": -1.0, "best_kd": -1.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['joint_name', 'total_trials', 'step_size_deg', 'best_trial_id', 'best_kp', 'best_ki', 'best_kd', 'best_overshoot_pct', 'best_settling_time_s', 'selection_criterion']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'total_trials': int(d.get('total_trials', 0)),
        'step_size_deg': float(d.get('step_size_deg', 0)),
        'best_trial_id': str(d.get('best_trial_id', '')),
        'best_kp': float(d.get('best_kp', -1)),
        'best_ki': float(d.get('best_ki', -1)),
        'best_kd': float(d.get('best_kd', -1))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_trials': 0, 'step_size_deg': 0.0, 'best_trial_id': '', 'best_kp': -1.0, 'best_ki': -1.0, 'best_kd': -1.0, 'error': str(e)}))
" 2>/dev/null || echo '{"has_fields": false, "total_trials": 0, "step_size_deg": 0.0, "best_trial_id": "", "best_kp": -1.0, "best_ki": -1.0, "best_kd": -1.0}')
fi

# Write result JSON
cat > /tmp/pid_tuning_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_info": $JSON_INFO
}
EOF

echo "=== Export Complete ==="