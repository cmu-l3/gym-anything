#!/bin/bash
echo "=== Exporting AGV Kinematic Swept Path Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/agv_swept_path_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/swept_corners.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/swept_report.json"

# Take final screenshot
take_screenshot /tmp/agv_swept_path_end_screenshot.png

# Check CSV file
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ANALYSIS='{"row_count": 0, "has_angle": false, "has_4_corners": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    # Analyze CSV using Python
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/swept_corners.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"row_count": 0, "has_angle": False, "has_4_corners": False}))
        sys.exit(0)
    
    headers = [h.strip().lower() for h in reader.fieldnames or []]
    
    has_angle = any('angle' in h for h in headers) or any('deg' in h for h in headers)
    
    # Check for all four corners (front-left, front-right, rear-left, rear-right)
    has_fl = any('front_left' in h for h in headers) or any('fl_' in h for h in headers)
    has_fr = any('front_right' in h for h in headers) or any('fr_' in h for h in headers)
    has_rl = any('rear_left' in h for h in headers) or any('rl_' in h for h in headers)
    has_rr = any('rear_right' in h for h in headers) or any('rr_' in h for h in headers)
    
    has_4_corners = has_fl and has_fr and has_rl and has_rr
    
    print(json.dumps({
        "row_count": len(rows),
        "has_angle": has_angle,
        "has_4_corners": has_4_corners
    }))
except Exception as e:
    print(json.dumps({"row_count": 0, "has_angle": False, "has_4_corners": False, "error": str(e)}))
PYEOF
    )
fi

# Check JSON report file
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_INFO='{"has_fields": false, "outer_radius_m": 0.0, "inner_radius_m": 0.0, "swept_width_m": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
    
    required = ['vehicle_length_m', 'vehicle_width_m', 'turn_radius_m', 'outer_radius_m', 'inner_radius_m', 'swept_width_m']
    has_fields = all(k in data for k in required)
    
    print(json.dumps({
        'has_fields': has_fields,
        'outer_radius_m': float(data.get('outer_radius_m', 0.0)),
        'inner_radius_m': float(data.get('inner_radius_m', 0.0)),
        'swept_width_m': float(data.get('swept_width_m', 0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'outer_radius_m': 0.0, 'inner_radius_m': 0.0, 'swept_width_m': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "outer_radius_m": 0.0, "inner_radius_m": 0.0, "swept_width_m": 0.0}')
fi

# Write combined result JSON
cat > /tmp/agv_swept_path_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_info": $JSON_INFO
}
EOF

echo "=== Export Complete ==="