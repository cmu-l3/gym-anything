#!/bin/bash
echo "=== Exporting vision_inspection_setup Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/vision_inspection_setup_start_ts 2>/dev/null || echo "0")
EXPORTS_DIR="/home/ga/Documents/CoppeliaSim/exports"
RGB_FILE="$EXPORTS_DIR/inspection_rgb.png"
DEPTH_FILE="$EXPORTS_DIR/inspection_depth.png"
CSV_FILE="$EXPORTS_DIR/scene_objects.csv"
JSON_FILE="$EXPORTS_DIR/inspection_report.json"

# Take final screenshot
take_screenshot /tmp/vision_inspection_setup_end.png

# 1. Check Images (Existence, Size, Creation Time)
RGB_EXISTS=false
RGB_IS_NEW=false
RGB_SIZE=0
if [ -f "$RGB_FILE" ]; then
    RGB_EXISTS=true
    RGB_SIZE=$(stat -c %s "$RGB_FILE" 2>/dev/null || echo "0")
    RGB_MTIME=$(stat -c %Y "$RGB_FILE" 2>/dev/null || echo "0")
    [ "$RGB_MTIME" -gt "$TASK_START" ] && RGB_IS_NEW=true
fi

DEPTH_EXISTS=false
DEPTH_IS_NEW=false
DEPTH_SIZE=0
if [ -f "$DEPTH_FILE" ]; then
    DEPTH_EXISTS=true
    DEPTH_SIZE=$(stat -c %s "$DEPTH_FILE" 2>/dev/null || echo "0")
    DEPTH_MTIME=$(stat -c %Y "$DEPTH_FILE" 2>/dev/null || echo "0")
    [ "$DEPTH_MTIME" -gt "$TASK_START" ] && DEPTH_IS_NEW=true
fi

# 2. Check CSV
CSV_EXISTS=false
CSV_IS_NEW=false
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true
fi

# 3. Check JSON
JSON_EXISTS=false
JSON_IS_NEW=false
if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON_FILE" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
fi

# 4. Analyze data using Python
# This script computes standard deviations of images (to prove they aren't blank)
# and analyzes the CSV/JSON contents for the verifier.
ANALYSIS=$(python3 << 'PYEOF'
import json, os, csv
import numpy as np
try:
    from PIL import Image
    has_pil = True
except:
    has_pil = False

res = {
    "rgb_std": 0.0,
    "depth_std": 0.0,
    "csv_rows": 0,
    "csv_has_cols": False,
    "csv_types_count": 0,
    "csv_x_spread": 0.0,
    "csv_y_spread": 0.0,
    "json_has_config": False,
    "json_has_stats": False,
    "error": None
}

try:
    # Image analysis
    if has_pil:
        if os.path.exists('/home/ga/Documents/CoppeliaSim/exports/inspection_rgb.png'):
            try:
                img = Image.open('/home/ga/Documents/CoppeliaSim/exports/inspection_rgb.png').convert('RGB')
                res["rgb_std"] = float(np.std(np.array(img)))
            except: pass
            
        if os.path.exists('/home/ga/Documents/CoppeliaSim/exports/inspection_depth.png'):
            try:
                dimg = Image.open('/home/ga/Documents/CoppeliaSim/exports/inspection_depth.png').convert('L')
                res["depth_std"] = float(np.std(np.array(dimg)))
            except: pass

    # CSV analysis
    csv_path = '/home/ga/Documents/CoppeliaSim/exports/scene_objects.csv'
    if os.path.exists(csv_path):
        with open(csv_path, 'r') as f:
            reader = list(csv.DictReader(f))
            res["csv_rows"] = len(reader)
            if len(reader) > 0:
                headers = [h.strip().lower() for h in reader[0].keys()]
                required = ['object_id', 'object_type', 'pos_x', 'pos_y', 'pos_z', 'color_r', 'color_g', 'color_b']
                res["csv_has_cols"] = all(r in headers for r in required)
                
                types = set()
                xs, ys = [], []
                for row in reader:
                    ot = row.get('object_type', row.get('type', ''))
                    types.add(ot.strip().lower())
                    try: xs.append(float(row.get('pos_x', 0)))
                    except: pass
                    try: ys.append(float(row.get('pos_y', 0)))
                    except: pass
                
                res["csv_types_count"] = len(types)
                if xs and ys:
                    res["csv_x_spread"] = max(xs) - min(xs)
                    res["csv_y_spread"] = max(ys) - min(ys)

    # JSON analysis
    json_path = '/home/ga/Documents/CoppeliaSim/exports/inspection_report.json'
    if os.path.exists(json_path):
        with open(json_path, 'r') as f:
            data = json.load(f)
            
            config_fields = ['sensor_resolution_x', 'sensor_resolution_y', 'sensor_position', 
                             'sensor_near_clip', 'sensor_far_clip', 'sensor_fov_deg']
            res["json_has_config"] = all(k in data for k in config_fields)
            
            stats_fields = ['total_objects_placed', 'rgb_mean_intensity', 'rgb_std_intensity', 
                            'depth_min_m', 'depth_max_m']
            res["json_has_stats"] = all(k in data for k in stats_fields)

except Exception as e:
    res["error"] = str(e)

print(json.dumps(res))
PYEOF
)

# Combine everything into the final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "rgb_exists": $RGB_EXISTS,
    "rgb_is_new": $RGB_IS_NEW,
    "rgb_size_bytes": $RGB_SIZE,
    "depth_exists": $DEPTH_EXISTS,
    "depth_is_new": $DEPTH_IS_NEW,
    "depth_size_bytes": $DEPTH_SIZE,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "analysis": $ANALYSIS
}
EOF

echo "=== Export Complete ==="