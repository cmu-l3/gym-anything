#!/bin/bash
echo "=== Exporting parallel_jaw_grasp_planning Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/parallel_jaw_grasp_planning_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/grasp_evaluations.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/optimal_grasp.json"

# Take final screenshot showing the generated scene
take_screenshot /tmp/parallel_jaw_grasp_planning_end_screenshot.png

# Initialize variables
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_required_cols": false, "valid_dual_contacts": 0, "spatial_variance": 0.0, "best_score": null, "error": "file missing"}'

# Analyze CSV
if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    # Read the row count
    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        print(len(list(csv.DictReader(f))))
except:
    print(0)
" 2>/dev/null || echo "0")

    # Deep parse the CSV contents to check diversity and contact logic
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

def is_truthy(val):
    return str(val).strip().lower() in ['true', '1', 'yes', 't', 'y']

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/grasp_evaluations.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"has_required_cols": False, "valid_dual_contacts": 0, "spatial_variance": 0.0, "best_score": None}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    
    # Required columns
    col_x = find_col(headers, ['x'])
    col_y = find_col(headers, ['y'])
    col_z = find_col(headers, ['z'])
    col_c1 = find_col(headers, ['contact1_detected', 'contact1', 'c1'])
    col_c2 = find_col(headers, ['contact2_detected', 'contact2', 'c2'])
    col_dot = find_col(headers, ['normal_dot_product', 'dot_product', 'dot'])
    col_score = find_col(headers, ['score', 'grasp_score'])
    
    has_cols = all(c is not None for c in [col_x, col_y, col_z, col_c1, col_c2, col_dot, col_score])
    
    valid_dual_contacts = 0
    xs, ys, zs = [], [], []
    best_score = None
    
    if has_cols:
        for r in rows:
            # Parse coords
            try:
                xs.append(float(r[col_x]))
                ys.append(float(r[col_y]))
                zs.append(float(r[col_z]))
            except ValueError:
                pass
                
            # Check dual contact
            if is_truthy(r[col_c1]) and is_truthy(r[col_c2]):
                try:
                    dot = float(r[col_dot])
                    if -1.01 <= dot <= 1.01:  # Math check bounds
                        valid_dual_contacts += 1
                except ValueError:
                    pass
            
            # Record best score mathematically (either max or min based on agent's function, just record max found for now)
            try:
                s = float(r[col_score])
                if best_score is None or s > best_score:
                    best_score = s
            except ValueError:
                pass

        # Calculate spatial variance (to prevent agent from staying in 1 spot)
        spatial_variance = 0.0
        if len(xs) > 1:
            mean_x, mean_y, mean_z = sum(xs)/len(xs), sum(ys)/len(ys), sum(zs)/len(zs)
            var_x = sum((x - mean_x)**2 for x in xs) / len(xs)
            var_y = sum((y - mean_y)**2 for y in ys) / len(ys)
            var_z = sum((z - mean_z)**2 for z in zs) / len(zs)
            spatial_variance = var_x + var_y + var_z

    print(json.dumps({
        "has_required_cols": has_cols,
        "valid_dual_contacts": valid_dual_contacts,
        "spatial_variance": spatial_variance,
        "best_score": best_score
    }))
except Exception as e:
    print(json.dumps({"has_required_cols": False, "valid_dual_contacts": 0, "spatial_variance": 0.0, "best_score": None, "error": str(e)}))
PYEOF
    )
fi

# Analyze JSON
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_FIELDS='{"has_fields": false, "total_poses": 0, "valid_grasps": 0, "best_score": null}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi

    JSON_FIELDS=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_poses_tested', 'valid_grasps_found', 'best_pose_id', 'best_score', 'best_pose_coords']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'total_poses': int(d.get('total_poses_tested', 0)),
        'valid_grasps': int(d.get('valid_grasps_found', 0)),
        'best_score': float(d.get('best_score', 0.0)) if d.get('best_score') is not None else None
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_poses': 0, 'valid_grasps': 0, 'best_score': None, 'error': str(e)}))
" 2>/dev/null || echo '{"has_fields": false, "total_poses": 0, "valid_grasps": 0, "best_score": null}')
fi

# Build final output
cat > /tmp/parallel_jaw_grasp_planning_result.json << EOF
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