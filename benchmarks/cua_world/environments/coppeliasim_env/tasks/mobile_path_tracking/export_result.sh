#!/bin/bash
echo "=== Exporting mobile_path_tracking Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/mobile_path_tracking_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/path_tracking.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/path_report.json"

# Take final screenshot
take_screenshot /tmp/mobile_path_tracking_end_screenshot.png

# Check CSV file
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_STATS='{"has_required_cols": false, "bb_width": 0.0, "bb_height": 0.0, "unique_positions": 0, "all_errors_non_negative": false, "path_length_m": 0.0}'

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

    CSV_STATS=$(python3 << 'PYEOF'
import csv, sys, json, math
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/path_tracking.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_required_cols": False, "bb_width": 0.0, "bb_height": 0.0, "unique_positions": 0, "all_errors_non_negative": False, "path_length_m": 0.0}))
        sys.exit(0)
        
    headers = [h.strip().lower() for h in rows[0].keys()]
    
    def get_col(candidates):
        for c in candidates:
            if c in headers:
                return list(rows[0].keys())[headers.index(c)]
        return None
        
    ax_col = get_col(['actual_x', 'x', 'pos_x'])
    ay_col = get_col(['actual_y', 'y', 'pos_y'])
    err_col = get_col(['tracking_error_m', 'error', 'error_m'])
    
    has_required = ax_col is not None and ay_col is not None and err_col is not None
    
    if has_required:
        xs, ys, errs = [], [], []
        for r in rows:
            try:
                xs.append(float(r[ax_col]))
                ys.append(float(r[ay_col]))
                errs.append(float(r[err_col]))
            except ValueError:
                pass
                
        if xs and ys:
            bb_width = max(xs) - min(xs)
            bb_height = max(ys) - min(ys)
            
            # Count unique rounded positions (to detect static robots)
            unique_pos = len(set((round(x, 2), round(y, 2)) for x, y in zip(xs, ys)))
            
            # Verify errors are valid distances
            all_non_negative = all(e >= 0.0 for e in errs)
            
            # Compute total distance to ensure actual movement occurred
            path_len = 0.0
            for i in range(1, len(xs)):
                path_len += math.sqrt((xs[i]-xs[i-1])**2 + (ys[i]-ys[i-1])**2)
        else:
            bb_width, bb_height, unique_pos, all_non_negative, path_len = 0.0, 0.0, 0, False, 0.0
    else:
        bb_width, bb_height, unique_pos, all_non_negative, path_len = 0.0, 0.0, 0, False, 0.0
        
    print(json.dumps({
        "has_required_cols": has_required,
        "bb_width": bb_width,
        "bb_height": bb_height,
        "unique_positions": unique_pos,
        "all_errors_non_negative": all_non_negative,
        "path_length_m": path_len
    }))
except Exception as e:
    print(json.dumps({"has_required_cols": False, "bb_width": 0.0, "bb_height": 0.0, "unique_positions": 0, "all_errors_non_negative": False, "path_length_m": 0.0, "error": str(e)}))
PYEOF
    )
fi

# Check JSON report file
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_INFO='{"has_fields": false, "total_samples": 0, "total_waypoints": 0, "distance": 0.0, "bb_w": 0.0, "bb_h": 0.0, "avg_err": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
    required = ['total_samples', 'total_waypoints', 'avg_tracking_error_m', 'max_tracking_error_m', 'total_distance_traveled_m', 'path_bounding_width_m', 'path_bounding_height_m']
    has_fields = all(k in data for k in required)
    
    print(json.dumps({
        'has_fields': has_fields,
        'total_samples': int(data.get('total_samples', 0)),
        'total_waypoints': int(data.get('total_waypoints', 0)),
        'distance': float(data.get('total_distance_traveled_m', 0.0)),
        'bb_w': float(data.get('path_bounding_width_m', 0.0)),
        'bb_h': float(data.get('path_bounding_height_m', 0.0)),
        'avg_err': float(data.get('avg_tracking_error_m', 0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_samples': 0, 'total_waypoints': 0, 'distance': 0.0, 'bb_w': 0.0, 'bb_h': 0.0, 'avg_err': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "total_samples": 0, "total_waypoints": 0, "distance": 0.0, "bb_w": 0.0, "bb_h": 0.0, "avg_err": 0.0}')
fi

# Write combined result JSON
cat > /tmp/mobile_path_tracking_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_stats": $CSV_STATS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_info": $JSON_INFO
}
EOF

echo "=== Export Complete ==="