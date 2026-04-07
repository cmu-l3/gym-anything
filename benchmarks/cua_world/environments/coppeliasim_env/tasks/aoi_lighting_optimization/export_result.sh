#!/bin/bash
echo "=== Exporting aoi_lighting_optimization Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/aoi_lighting_optimization_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/lighting_sweep.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/lighting_report.json"
PNG="/home/ga/Documents/CoppeliaSim/exports/optimal_inspection.png"

# Take final screenshot
take_screenshot /tmp/aoi_lighting_optimization_end_screenshot.png

# Initialize variables
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0

# Check CSV
if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        print(len(list(csv.DictReader(f))))
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
    with open('/home/ga/Documents/CoppeliaSim/exports/lighting_sweep.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_cols": False, "is_hemisphere": False, "contrast_variance": 0.0, "max_contrast": 0.0}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    cx = find_col(headers, ['light_x', 'x'])
    cy = find_col(headers, ['light_y', 'y'])
    cz = find_col(headers, ['light_z', 'z'])
    cc = find_col(headers, ['contrast_metric', 'contrast', 'metric'])
    
    has_cols = all(c is not None for c in [cx, cy, cz, cc])
    
    is_hemisphere = False
    contrast_variance = 0.0
    max_contrast = 0.0
    best_pose_id = ""
    
    if has_cols:
        xs, ys, zs, cs = [], [], [], []
        for i, r in enumerate(rows):
            try:
                xs.append(float(r[cx]))
                ys.append(float(r[cy]))
                zs.append(float(r[cz]))
                cs.append(float(r[cc]))
            except:
                pass
                
        if len(xs) > 1:
            # Hemispherical validation: constant radius and z >= 0
            radii = [math.sqrt(x**2 + y**2 + z**2) for x,y,z in zip(xs, ys, zs)]
            mean_r = sum(radii) / len(radii)
            var_r = sum((r - mean_r)**2 for r in radii) / len(radii)
            # Variance must be small relative to mean radius (allows slight inaccuracies), z mostly above ground
            is_hemisphere = (var_r < 0.05 * mean_r) and all(z >= -0.05 for z in zs) and mean_r > 0
            
            # Contrast validation
            mean_c = sum(cs) / len(cs)
            contrast_variance = sum((c - mean_c)**2 for c in cs) / len(cs)
            max_contrast = max(cs)
            
            # Find best pose ID corresponding to max contrast
            c_id = find_col(headers, ['pose_id', 'id'])
            if c_id:
                best_idx = cs.index(max_contrast)
                best_pose_id = str(rows[best_idx].get(c_id, ''))
                
    print(json.dumps({
        "has_cols": has_cols, 
        "is_hemisphere": is_hemisphere, 
        "contrast_variance": contrast_variance, 
        "max_contrast": max_contrast,
        "csv_best_pose_id": best_pose_id
    }))
except Exception as e:
    print(json.dumps({"has_cols": False, "is_hemisphere": False, "contrast_variance": 0.0, "max_contrast": 0.0, "error": str(e)}))
PYEOF
    )
else:
    CSV_ANALYSIS='{"has_cols": false, "is_hemisphere": false, "contrast_variance": 0.0, "max_contrast": 0.0}'
fi

# Check JSON
JSON_EXISTS=false
JSON_IS_NEW=false
if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_positions_tested', 'best_pose_id', 'best_x', 'best_y', 'best_z', 'max_contrast_metric', 'min_contrast_metric']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields, 
        'total': int(d.get('total_positions_tested', 0)), 
        'max_contrast': float(d.get('max_contrast_metric', 0.0)),
        'best_pose_id': str(d.get('best_pose_id', ''))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total': 0, 'max_contrast': 0.0, 'best_pose_id': ''}))
" 2>/dev/null || echo '{"has_fields": false, "total": 0, "max_contrast": 0.0, "best_pose_id": ""}')
else:
    JSON_FIELDS='{"has_fields": false, "total": 0, "max_contrast": 0.0, "best_pose_id": ""}'
fi

# Check PNG image validity
PNG_EXISTS=false
PNG_IS_NEW=false
if [ -f "$PNG" ]; then
    PNG_EXISTS=true
    PNG_MTIME=$(stat -c %Y "$PNG" 2>/dev/null || echo "0")
    [ "$PNG_MTIME" -gt "$TASK_START" ] && PNG_IS_NEW=true
    PNG_ANALYSIS=$(python3 -c "
import json
try:
    from PIL import Image
    import numpy as np
    img = Image.open('$PNG')
    arr = np.array(img)
    std_dev = float(np.std(arr))
    print(json.dumps({'valid': True, 'std_dev': std_dev, 'is_solid': std_dev < 1.0}))
except Exception as e:
    print(json.dumps({'valid': False, 'std_dev': 0.0, 'is_solid': True, 'error': str(e)}))
" 2>/dev/null || echo '{"valid": false, "std_dev": 0.0, "is_solid": true}')
else:
    PNG_ANALYSIS='{"valid": false, "std_dev": 0.0, "is_solid": true}'
fi

cat > /tmp/aoi_lighting_optimization_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS,
    "png_exists": $PNG_EXISTS,
    "png_is_new": $PNG_IS_NEW,
    "png_analysis": $PNG_ANALYSIS
}
EOF

echo "=== Export Complete ==="