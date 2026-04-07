#!/bin/bash
echo "=== Exporting camera_occlusion_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/camera_occlusion_analysis_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/occlusion_data.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/occlusion_report.json"

take_screenshot /tmp/camera_occlusion_analysis_end.png

CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_columns": false, "num_cameras": 0, "num_configs": 0, "occlusion_variance": false, "total_samples": 0}'

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
    with open('/home/ga/Documents/CoppeliaSim/exports/occlusion_data.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_columns": False, "num_cameras": 0, "num_configs": 0, "occlusion_variance": False, "total_samples": 0}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    cam_col = find_col(headers, ['camera_id', 'cam_id', 'camera'])
    conf_col = find_col(headers, ['config_id', 'configuration', 'config'])
    occ_col = find_col(headers, ['is_occluded', 'occluded', 'occlusion'])
    
    has_columns = cam_col is not None and conf_col is not None and occ_col is not None
    
    if has_columns:
        cameras = set()
        configs = set()
        occlusions = set()
        for r in rows:
            if r.get(cam_col, "").strip():
                cameras.add(r[cam_col])
            if r.get(conf_col, "").strip():
                configs.add(r[conf_col])
            occ_val = str(r.get(occ_col, "")).strip().lower()
            if occ_val in ['1', 'true', 'yes', 't', 'y']:
                occlusions.add(True)
            elif occ_val in ['0', 'false', 'no', 'f', 'n']:
                occlusions.add(False)
        
        num_cameras = len(cameras)
        num_configs = len(configs)
        # Check variance: both True and False must exist
        occlusion_variance = (True in occlusions) and (False in occlusions)
        total_samples = len(rows)
    else:
        num_cameras = 0
        num_configs = 0
        occlusion_variance = False
        total_samples = 0
        
    print(json.dumps({
        "has_columns": has_columns,
        "num_cameras": num_cameras,
        "num_configs": num_configs,
        "occlusion_variance": occlusion_variance,
        "total_samples": total_samples
    }))
except Exception as e:
    print(json.dumps({
        "has_columns": False,
        "num_cameras": 0,
        "num_configs": 0,
        "occlusion_variance": False,
        "total_samples": 0,
        "error": str(e)
    }))
PYEOF
    )
fi

JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_FIELDS='{"has_fields": false, "total_cameras_tested": 0, "total_configs_tested": 0, "best_visibility_pct": 0.0}'

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
    req = ['total_cameras_tested', 'total_configs_tested', 'target_position', 'best_camera_id', 'best_visibility_pct', 'worst_visibility_pct']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'total_cameras_tested': int(d.get('total_cameras_tested', 0)),
        'total_configs_tested': int(d.get('total_configs_tested', 0)),
        'best_visibility_pct': float(d.get('best_visibility_pct', 0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_cameras_tested': 0, 'total_configs_tested': 0, 'best_visibility_pct': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "total_cameras_tested": 0, "total_configs_tested": 0, "best_visibility_pct": 0.0}')
fi

cat > /tmp/camera_occlusion_analysis_result.json << EOF
{
    "task_start": $TASK_START,
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