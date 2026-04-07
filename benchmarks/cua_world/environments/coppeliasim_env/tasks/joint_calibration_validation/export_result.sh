#!/bin/bash
echo "=== Exporting joint_calibration_validation Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/joint_calibration_validation_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/calibration_results.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/calibration_report.json"

take_screenshot /tmp/joint_calibration_validation_end_screenshot.png

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_positions": false, "has_errors": false, "joint_range_deg": 0.0, "configs_with_error": 0}'

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
    with open('/home/ga/Documents/CoppeliaSim/exports/calibration_results.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_positions": False, "has_errors": False, "joint_range_deg": 0.0, "configs_with_error": 0}))
        sys.exit(0)
    headers = list(rows[0].keys())
    # Position columns
    mx = find_col(headers, ['measured_x','actual_x','x_m','x'])
    my = find_col(headers, ['measured_y','actual_y','y_m','y'])
    mz = find_col(headers, ['measured_z','actual_z','z_m','z'])
    # Error column
    err_col = find_col(headers, ['position_error_mm','error_mm','error'])
    # Joint column (check j0)
    j0_col = find_col(headers, ['j0_deg','j0','joint0','q0'])
    has_positions = mx is not None and my is not None and mz is not None
    has_errors = err_col is not None
    # Joint range: find max range across all joint columns
    joint_range = 0.0
    for jcol_name in ['j0_deg','j1_deg','j2_deg','j0','j1','j2']:
        jcol = find_col(headers, [jcol_name])
        if jcol:
            try:
                vals = [float(r[jcol]) for r in rows if r.get(jcol,'').strip()]
                if vals:
                    r_range = max(vals) - min(vals)
                    joint_range = max(joint_range, r_range)
            except:
                pass
    # Count configs with error data
    if has_errors:
        configs_with_error = sum(1 for r in rows if r.get(err_col,'').strip())
    else:
        configs_with_error = 0
    print(json.dumps({"has_positions": has_positions, "has_errors": has_errors,
                      "joint_range_deg": joint_range, "configs_with_error": configs_with_error}))
except Exception as e:
    print(json.dumps({"has_positions": False, "has_errors": False, "joint_range_deg": 0.0, "configs_with_error": 0, "error": str(e)}))
PYEOF
    )
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_configs": 0, "flagged_count": 0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_configs','flagged_count','max_error_mm','pass_rate_pct']
    has_fields = all(k in d for k in req)
    print(json.dumps({'has_fields': has_fields, 'total_configs': int(d.get('total_configs',0)), 'flagged_count': int(d.get('flagged_count',0))}))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_configs': 0, 'flagged_count': 0}))
" 2>/dev/null || echo '{"has_fields": false, "total_configs": 0, "flagged_count": 0}')
fi

cat > /tmp/joint_calibration_validation_result.json << EOF
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
