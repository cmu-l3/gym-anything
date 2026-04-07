#!/bin/bash
echo "=== Exporting robot_cmm_calibration_scan Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/robot_cmm_calibration_scan_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/scan_data.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/calibration_metrics.json"
TTT="/home/ga/Documents/CoppeliaSim/exports/calibration_setup.ttt"

# Take final screenshot
take_screenshot /tmp/robot_cmm_calibration_scan_end_screenshot.png

# Check TTT file (Scene Artifact)
TTT_EXISTS=false
TTT_IS_NEW=false
TTT_SIZE=0

if [ -f "$TTT" ]; then
    TTT_EXISTS=true
    TTT_MTIME=$(stat -c %Y "$TTT" 2>/dev/null || echo "0")
    [ "$TTT_MTIME" -gt "$TASK_START" ] && TTT_IS_NEW=true
    TTT_SIZE=$(stat -c %s "$TTT" 2>/dev/null || echo "0")
fi

# Check CSV Data
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_required_cols": false, "surface_z_values": []}'

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

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/scan_data.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_required_cols": False, "surface_z_values": []}))
        sys.exit(0)
    headers = list(rows[0].keys())
    
    ee_z_col = find_col(headers, ['ee_z', 'z', 'end_effector_z'])
    sensor_dist_col = find_col(headers, ['sensor_dist', 'distance', 'dist'])
    surface_z_col = find_col(headers, ['surface_z', 'height', 'surface_height'])
    
    has_required_cols = ee_z_col is not None and sensor_dist_col is not None and surface_z_col is not None
    
    surface_z_vals = []
    if has_required_cols:
        for r in rows:
            try:
                val = float(r[surface_z_col])
                surface_z_vals.append(val)
            except:
                pass
                
    print(json.dumps({
        "has_required_cols": has_required_cols, 
        "surface_z_values": surface_z_vals
    }))
except Exception as e:
    print(json.dumps({"has_required_cols": False, "surface_z_values": [], "error": str(e)}))
PYEOF
    )
fi

# Check JSON Data
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
    req = ['total_samples', 'steps_detected', 'max_surface_z_m', 'min_surface_z_m']
    has_fields = all(k in d for k in req)
    print(json.dumps({'has_fields': has_fields}))
except Exception as e:
    print(json.dumps({'has_fields': False}))
" 2>/dev/null || echo '{"has_fields": false}')
fi

# Write Verification Data 
cat > /tmp/robot_cmm_calibration_scan_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS,
    "ttt_exists": $TTT_EXISTS,
    "ttt_is_new": $TTT_IS_NEW,
    "ttt_size": $TTT_SIZE
}
EOF

echo "=== Export Complete ==="