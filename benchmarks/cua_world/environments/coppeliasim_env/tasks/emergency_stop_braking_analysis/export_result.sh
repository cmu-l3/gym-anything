#!/bin/bash
echo "=== Exporting emergency_stop_braking_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/braking_analysis_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/braking_analysis.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/safety_report.json"

# Take final screenshot
take_screenshot /tmp/braking_analysis_end_screenshot.png

# Check CSV file
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ANALYSIS='{"has_cols": false, "row_count": 0, "tests": []}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW="true"

    # Evaluate CSV contents robustly using python
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, sys, json

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/braking_analysis.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_cols": False, "row_count": 0, "tests": []}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    
    # Tolerant column matching
    v_col = find_col(headers, ['initial_velocity_rad_s', 'initial_velocity', 'velocity'])
    tq_col = find_col(headers, ['brake_torque_nm', 'brake_torque', 'torque'])
    t_col = find_col(headers, ['braking_time_s', 'braking_time', 'time'])
    d_col = find_col(headers, ['braking_distance_rad', 'braking_distance', 'distance'])
    
    has_cols = v_col and tq_col and t_col and d_col
    tests = []
    
    if has_cols:
        for r in rows:
            try:
                tests.append({
                    "v": float(r[v_col]),
                    "tq": float(r[tq_col]),
                    "t": float(r[t_col]),
                    "d": float(r[d_col])
                })
            except Exception:
                pass
                
    print(json.dumps({
        "has_cols": bool(has_cols),
        "row_count": len(rows),
        "tests": tests
    }))
except Exception as e:
    print(json.dumps({"has_cols": False, "row_count": 0, "tests": [], "error": str(e)}))
PYEOF
    )
fi

# Check JSON report file
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_FIELDS='{"has_fields": false, "total_tests": 0, "max_braking_distance_rad": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW="true"

    JSON_FIELDS=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_tests', 'max_braking_distance_rad', 'max_braking_time_s', 'average_deceleration_rad_s2']
    has_fields = all(k in d for k in req)
    
    print(json.dumps({
        'has_fields': has_fields,
        'total_tests': int(d.get('total_tests', 0)),
        'max_braking_distance_rad': float(d.get('max_braking_distance_rad', 0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_tests': 0, 'max_braking_distance_rad': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "total_tests": 0, "max_braking_distance_rad": 0.0}')
fi

# Write result JSON carefully to bypass filesystem block issues
TEMP_JSON=$(mktemp /tmp/braking_analysis_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS
}
EOF

rm -f /tmp/braking_analysis_result.json 2>/dev/null || sudo rm -f /tmp/braking_analysis_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/braking_analysis_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/braking_analysis_result.json
chmod 666 /tmp/braking_analysis_result.json 2>/dev/null || sudo chmod 666 /tmp/braking_analysis_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="