#!/bin/bash
echo "=== Exporting visual_servoing_tracking Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/visual_servoing_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/tracking_log.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/servoing_report.json"
FRAMES_DIR="/home/ga/Documents/CoppeliaSim/exports/frames"

# Take final screenshot
take_screenshot /tmp/visual_servoing_end_screenshot.png

# 1. Analyze CSV Output
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_STATS='{"valid": false, "row_count": 0, "max_std_m": 0.0, "avg_err_px": 999.0, "bbox_varies": false, "bbox_positive": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    CSV_STATS=$(python3 << 'PYEOF'
import csv, json, sys, statistics

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/tracking_log.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    if not rows:
        print(json.dumps({"valid": False, "row_count": 0, "max_std_m": 0.0, "avg_err_px": 999.0, "bbox_varies": False, "bbox_positive": False}))
        sys.exit(0)

    headers = list(rows[0].keys())
    
    # Locate required columns robustly
    x_col = find_col(headers, ['target_world_x', 'target_x', 'tx', 'x'])
    y_col = find_col(headers, ['target_world_y', 'target_y', 'ty', 'y'])
    z_col = find_col(headers, ['target_world_z', 'target_z', 'tz', 'z'])
    err_col = find_col(headers, ['error_magnitude_px', 'error_px', 'error', 'err'])
    bbox_col = find_col(headers, ['bbox_area_px', 'bbox_area', 'area'])

    if not all([x_col, y_col, z_col, err_col, bbox_col]):
        print(json.dumps({"valid": False, "row_count": len(rows), "reason": "Missing required columns"}))
        sys.exit(0)

    # Extract data
    xs, ys, zs, errs, areas = [], [], [], [], []
    for r in rows:
        try:
            xs.append(float(r[x_col]))
            ys.append(float(r[y_col]))
            zs.append(float(r[z_col]))
            errs.append(float(r[err_col]))
            areas.append(float(r[bbox_col]))
        except (ValueError, TypeError):
            pass

    # Compute statistics
    std_x = statistics.stdev(xs) if len(xs) > 1 else 0.0
    std_y = statistics.stdev(ys) if len(ys) > 1 else 0.0
    std_z = statistics.stdev(zs) if len(zs) > 1 else 0.0
    max_std = max(std_x, std_y, std_z)

    avg_err = sum(errs) / len(errs) if errs else 999.0
    
    bbox_varies = (max(areas) - min(areas) > 0) if areas else False
    bbox_positive = all(a > 0 for a in areas) if areas else False

    print(json.dumps({
        "valid": True,
        "row_count": len(rows),
        "max_std_m": max_std,
        "avg_err_px": avg_err,
        "bbox_varies": bbox_varies,
        "bbox_positive": bbox_positive
    }))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# 2. Analyze JSON Report
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_FIELDS='{"valid": false, "total_frames": 0, "avg_error": 999.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi

    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_frames', 'avg_error_px', 'max_error_px']
    valid = all(k in d for k in req)
    print(json.dumps({
        'valid': valid,
        'total_frames': int(d.get('total_frames', 0)),
        'avg_error': float(d.get('avg_error_px', 999.0))
    }))
except Exception as e:
    print(json.dumps({'valid': False, 'total_frames': 0, 'avg_error': 999.0}))
" 2>/dev/null || echo '{"valid": false}')
fi

# 3. Analyze Exported Frames
FRAMES_COUNT=$(find "$FRAMES_DIR" -maxdepth 1 -type f -name "*.png" -newermt "@$TASK_START" 2>/dev/null | wc -l)

# 4. Write Unified Result JSON
cat > /tmp/visual_servoing_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_stats": $CSV_STATS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS,
    "frames_count": $FRAMES_COUNT
}
EOF

echo "=== Export Complete ==="
cat /tmp/visual_servoing_result.json