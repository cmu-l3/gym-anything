#!/bin/bash
echo "=== Exporting camera_intrinsic_calibration_sim Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/camera_calib_start_ts 2>/dev/null || echo "0")
EXPORTS_DIR="/home/ga/Documents/CoppeliaSim/exports"
CSV="$EXPORTS_DIR/calibration_poses.csv"
JSON="$EXPORTS_DIR/calibration_results.json"
IMG_DIR="$EXPORTS_DIR/calib_images"

# Take final screenshot
take_screenshot /tmp/camera_calib_end_screenshot.png

# 1. Check Images
IMG_COUNT=0
if [ -d "$IMG_DIR" ]; then
    # Count PNGs created after the task started
    IMG_COUNT=$(find "$IMG_DIR" -type f -name "*.png" -newer /tmp/camera_calib_start_marker 2>/dev/null | wc -l)
fi

# 2. Check CSV File
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_coords": false, "variance_sum": 0.0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW="true"

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
    def variance(data):
        n = len(data)
        if n < 2: return 0.0
        mean = sum(data) / n
        return sum((x - mean) ** 2 for x in data) / (n - 1)

    with open('/home/ga/Documents/CoppeliaSim/exports/calibration_poses.csv') as f:
        rows = list(csv.DictReader(f))
    
    if not rows:
        print(json.dumps({"has_coords": False, "variance_sum": 0.0}))
        sys.exit(0)
        
    headers = [h.strip().lower() for h in rows[0].keys()]
    x_col = next((h for h in headers if h in ['pos_x', 'x', 'x_m']), None)
    y_col = next((h for h in headers if h in ['pos_y', 'y', 'y_m']), None)
    z_col = next((h for h in headers if h in ['pos_z', 'z', 'z_m']), None)
    
    has_coords = x_col and y_col and z_col
    var_sum = 0.0
    
    if has_coords:
        try:
            xs = [float(r[x_col]) for r in rows if r[x_col].strip()]
            ys = [float(r[y_col]) for r in rows if r[y_col].strip()]
            zs = [float(r[z_col]) for r in rows if r[z_col].strip()]
            var_sum = variance(xs) + variance(ys) + variance(zs)
        except:
            pass
            
    print(json.dumps({"has_coords": bool(has_coords), "variance_sum": var_sum}))
except Exception as e:
    print(json.dumps({"has_coords": False, "variance_sum": 0.0, "error": str(e)}))
PYEOF
    )
fi

# 3. Check JSON Report File
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_FIELDS='{"has_fields": false, "estimated_fx": 0.0, "estimated_fy": 0.0, "total_images_captured": 0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW="true"

    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        data = json.load(f)
    req = ['total_images_captured', 'estimated_fx', 'estimated_fy', 'reprojection_error']
    has_fields = all(k in data for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'estimated_fx': float(data.get('estimated_fx', 0.0)),
        'estimated_fy': float(data.get('estimated_fy', 0.0)),
        'total_images_captured': int(data.get('total_images_captured', 0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'estimated_fx': 0.0, 'estimated_fy': 0.0, 'total_images_captured': 0}))
" 2>/dev/null || echo '{"has_fields": false, "estimated_fx": 0.0, "estimated_fy": 0.0, "total_images_captured": 0}')
fi

# Write result JSON for the verifier
cat > /tmp/camera_calib_result.json << EOF
{
    "task_start": $TASK_START,
    "image_count": $IMG_COUNT,
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