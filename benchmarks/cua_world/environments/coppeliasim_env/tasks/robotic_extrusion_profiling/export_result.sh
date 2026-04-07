#!/bin/bash
echo "=== Exporting robotic_extrusion_profiling Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/robotic_extrusion_profiling_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/extrusion_profile.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/extrusion_report.json"

# Take final screenshot
take_screenshot /tmp/robotic_extrusion_profiling_end_screenshot.png

# Check CSV file
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_data": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        print(len(list(csv.DictReader(f))))
except:
    print(0)
" 2>/dev/null || echo "0")

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/extrusion_profile.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_data": False}))
        sys.exit(0)
        
    headers = [h.strip().lower() for h in rows[0].keys()]
    
    def get_col(*cands):
        for c in cands:
            if c in headers: return list(rows[0].keys())[headers.index(c)]
        return None
        
    ax_c = get_col('actual_x', 'x_actual', 'x')
    ay_c = get_col('actual_y', 'y_actual', 'y')
    v_c = get_col('velocity_m_s', 'velocity', 'vel')
    te_c = get_col('tracking_error_m', 'tracking_error', 'error')

    ax_vals = [float(r[ax_c]) for r in rows if r.get(ax_c, '').strip()] if ax_c else []
    ay_vals = [float(r[ay_c]) for r in rows if r.get(ay_c, '').strip()] if ay_c else []
    v_vals = [float(r[v_c]) for r in rows if r.get(v_c, '').strip()] if v_c else []
    te_vals = [float(r[te_c]) for r in rows if r.get(te_c, '').strip()] if te_c else []

    x_range = max(ax_vals) - min(ax_vals) if ax_vals else 0.0
    y_range = max(ay_vals) - min(ay_vals) if ay_vals else 0.0
    mean_v = sum(v_vals) / len(v_vals) if v_vals else 0.0
    max_te = max(te_vals) if te_vals else 0.0

    print(json.dumps({
        "has_data": True,
        "x_range": x_range,
        "y_range": y_range,
        "mean_v": mean_v,
        "max_te": max_te,
        "cols_found": {
            "ax": ax_c is not None,
            "ay": ay_c is not None,
            "v": v_c is not None,
            "te": te_c is not None
        }
    }))
except Exception as e:
    print(json.dumps({"has_data": False, "error": str(e)}))
PYEOF
    )
fi

# Check JSON report file
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_INFO='{"has_fields": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi

    JSON_INFO=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        data = json.load(f)
    required = ['total_samples', 'path_length_m', 'mean_velocity_m_s', 'max_tracking_error_m']
    has_fields = all(k in data for k in required)
    print(json.dumps({
        'has_fields': has_fields, 
        'mean_v': float(data.get('mean_velocity_m_s', 0.0)), 
        'total_samples': int(data.get('total_samples', 0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'error': str(e)}))
" 2>/dev/null || echo '{"has_fields": false}')
fi

# Write result JSON
TEMP_JSON=$(mktemp /tmp/extrusion_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_stats": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_info": $JSON_INFO
}
EOF

rm -f /tmp/robotic_extrusion_profiling_result.json 2>/dev/null || sudo rm -f /tmp/robotic_extrusion_profiling_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/robotic_extrusion_profiling_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/robotic_extrusion_profiling_result.json
chmod 666 /tmp/robotic_extrusion_profiling_result.json 2>/dev/null || sudo chmod 666 /tmp/robotic_extrusion_profiling_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="