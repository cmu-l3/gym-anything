#!/bin/bash
echo "=== Exporting light_curtain_safety_validation Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/light_curtain_task_start_ts 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/CoppeliaSim/exports/light_curtain_breaches.csv"
JSON_PATH="/home/ga/Documents/CoppeliaSim/exports/safety_report.json"

# Capture final state screenshot
take_screenshot /tmp/light_curtain_task_end_screenshot.png

# Check if CoppeliaSim is still running
APP_RUNNING=$(pgrep -f "coppeliaSim" > /dev/null && echo "true" || echo "false")

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_cols": false, "unique_times": 0, "min_z": 0.0, "max_z": 0.0}'

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW=true
    fi

    # Parse and analyze the CSV
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/light_curtain_breaches.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"has_cols": False, "unique_times": 0, "min_z": 0.0, "max_z": 0.0, "row_count": 0}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    
    col_time = find_col(headers, ['sim_time_s', 'time', 'sim_time'])
    col_z = find_col(headers, ['sensor_z_m', 'z_m', 'sensor_z', 'z'])
    col_idx = find_col(headers, ['sensor_index', 'index', 'sensor_id'])
    
    has_cols = col_time is not None and col_z is not None and col_idx is not None
    
    unique_times = set()
    zs = []
    
    if has_cols:
        for r in rows:
            try:
                unique_times.add(float(r[col_time]))
                zs.append(float(r[col_z]))
            except ValueError:
                pass
                
    min_z = min(zs) if zs else 0.0
    max_z = max(zs) if zs else 0.0
    
    print(json.dumps({
        "has_cols": has_cols,
        "unique_times": len(unique_times),
        "min_z": min_z,
        "max_z": max_z,
        "row_count": len(rows)
    }))
except Exception as e:
    print(json.dumps({"has_cols": False, "unique_times": 0, "min_z": 0.0, "max_z": 0.0, "row_count": 0, "error": str(e)}))
PYEOF
    )
    
    CSV_ROW_COUNT=$(echo "$CSV_ANALYSIS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('row_count', 0))")
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_sensors": 0, "sensors_triggered": 0}'

if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW=true
    fi

    # Parse JSON
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON_PATH') as f:
        d = json.load(f)
    req = ['total_sensors', 'sensors_triggered_count', 'first_breach_time_s', 'first_breach_sensor_index', 'lowest_breach_z_m', 'highest_breach_z_m']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'total_sensors': int(d.get('total_sensors', 0)),
        'sensors_triggered': int(d.get('sensors_triggered_count', 0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_sensors': 0, 'sensors_triggered': 0}))
" 2>/dev/null || echo '{"has_fields": false, "total_sensors": 0, "sensors_triggered": 0}')
fi

# Write summary to a single result file
cat > /tmp/light_curtain_result.json << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS
}
EOF

echo "Result saved to /tmp/light_curtain_result.json"
echo "=== Export Complete ==="