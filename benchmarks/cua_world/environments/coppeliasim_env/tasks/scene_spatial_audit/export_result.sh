#!/bin/bash
echo "=== Exporting scene_spatial_audit Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/scene_spatial_audit_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/scene_inventory.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/spatial_analysis.json"

# Take final evidence screenshot
take_screenshot /tmp/scene_spatial_audit_end_screenshot.png

# --- Analyze CSV ---
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ANALYSIS='{"error": "not evaluated", "row_count": 0, "num_types": 0, "max_std_pos": 0.0, "has_positive_bbox": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW=true
    fi

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

def get_val(row, candidates):
    for c in candidates:
        for k in row.keys():
            if k and c.lower() in k.strip().lower():
                return row[k]
    return ''

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/scene_inventory.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"row_count": 0, "num_types": 0, "max_std_pos": 0.0, "has_positive_bbox": False}))
        sys.exit(0)
    
    # Types diversity
    types = set(get_val(r, ['type']).strip() for r in rows if get_val(r, ['type']).strip())
    
    # Position diversity (Standard Deviation)
    xs = [float(get_val(r, ['pos_x', 'x', 'px'])) for r in rows if get_val(r, ['pos_x', 'x', 'px']).strip()]
    ys = [float(get_val(r, ['pos_y', 'y', 'py'])) for r in rows if get_val(r, ['pos_y', 'y', 'py']).strip()]
    zs = [float(get_val(r, ['pos_z', 'z', 'pz'])) for r in rows if get_val(r, ['pos_z', 'z', 'pz']).strip()]
    
    def std_dev(lst):
        if len(lst) < 2: return 0.0
        mean = sum(lst) / len(lst)
        return math.sqrt(sum((x - mean)**2 for x in lst) / len(lst))
    
    max_std = max(std_dev(xs), std_dev(ys), std_dev(zs)) if xs else 0.0
    
    # Bbox Check
    bboxes = []
    for r in rows:
        bx = get_val(r, ['bbox_x', 'bx'])
        if bx.strip():
            try: bboxes.append(float(bx))
            except: pass
            
    has_positive_bbox = any(b > 0 for b in bboxes)
    
    print(json.dumps({
        "row_count": len(rows),
        "num_types": len(types),
        "max_std_pos": max_std,
        "has_positive_bbox": has_positive_bbox
    }))
except Exception as e:
    print(json.dumps({
        "error": str(e),
        "row_count": 0,
        "num_types": 0,
        "max_std_pos": 0.0,
        "has_positive_bbox": False
    }))
PYEOF
    )
fi

# --- Analyze JSON ---
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_ANALYSIS='{"error": "not evaluated", "has_fields": false, "total_objects": 0, "nearest_dist": 0.0, "clearance_pairs_count": 0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW=true
    fi

    JSON_ANALYSIS=$(python3 << 'PYEOF'
import json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/spatial_analysis.json') as f:
        d = json.load(f)
    
    req_fields = [
        'total_objects', 'joint_count', 'shape_count', 'dummy_count', 
        'robot_base_name', 'robot_base_xyz', 'nearest_obstacle_name', 
        'nearest_obstacle_distance_m', 'scene_bbox_min', 'scene_bbox_max', 
        'clearance_pairs'
    ]
    
    has_fields = all(k in d for k in req_fields)
    total_obj = int(d.get('total_objects', 0))
    dist = float(d.get('nearest_obstacle_distance_m', 0.0))
    
    pairs = d.get('clearance_pairs', [])
    pairs_count = len(pairs) if isinstance(pairs, list) else 0
    
    print(json.dumps({
        "has_fields": has_fields,
        "total_objects": total_obj,
        "nearest_dist": dist,
        "clearance_pairs_count": pairs_count
    }))
except Exception as e:
    print(json.dumps({
        "error": str(e),
        "has_fields": False,
        "total_objects": 0,
        "nearest_dist": 0.0,
        "clearance_pairs_count": 0
    }))
PYEOF
    )
fi

# Assemble complete result payload
cat > /tmp/scene_spatial_audit_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_analysis": $JSON_ANALYSIS
}
EOF

echo "=== Export Complete ==="