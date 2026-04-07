#!/bin/bash
echo "=== Exporting kinematic_chain_build Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/kinematic_chain_build_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/kinematic_sweep.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/kinematic_model.json"

take_screenshot /tmp/kinematic_chain_build_end_screenshot.png

# 1. Check Scene State via ZMQ API
echo "Querying live scene state via ZMQ..."
ZMQ_ANALYSIS=$(python3 << 'PYEOF'
import sys, json

sys.path.insert(0, '/opt/CoppeliaSim/programming/zmqRemoteApi/clients/python/src')
try:
    from coppeliasim_zmqremoteapi_client import RemoteAPIClient
    client = RemoteAPIClient()
    sim = client.require('sim')
    
    # 0 = object_shape_type, 1 = object_joint_type
    all_joints = sim.getObjectsWithFlags(sim.object_joint_type, sim.handle_all)
    all_shapes = sim.getObjectsWithFlags(sim.object_shape_type, sim.handle_all)
    
    rev_joints = 0
    for j in all_joints:
        if sim.getJointType(j) == sim.joint_revolute_subtype:
            rev_joints += 1
            
    print(json.dumps({
        "zmq_success": True,
        "revolute_joints_count": rev_joints,
        "shapes_count": len(all_shapes)
    }))
except Exception as e:
    print(json.dumps({
        "zmq_success": False,
        "revolute_joints_count": 0,
        "shapes_count": 0,
        "error": str(e)
    }))
PYEOF
)

# 2. Check CSV
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_positions": false, "has_error": false, "rows_with_low_error": 0, "spatial_range_m": 0.0, "joint_span_deg": 0.0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ROW_COUNT=$(python3 -c "import csv; print(len(list(csv.DictReader(open('$CSV')))))" 2>/dev/null || echo "0")

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/kinematic_sweep.csv') as f:
        rows = list(csv.DictReader(f))
    if not rows:
        print(json.dumps({"has_positions": False, "has_error": False, "rows_with_low_error": 0, "spatial_range_m": 0.0, "joint_span_deg": 0.0}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    
    x_col = find_col(headers, ['ee_x', 'x', 'measured_x', 'actual_x'])
    y_col = find_col(headers, ['ee_y', 'y', 'measured_y', 'actual_y'])
    err_col = find_col(headers, ['fk_error_mm', 'error_mm', 'error', 'position_error'])
    
    has_positions = x_col is not None and y_col is not None
    has_error = err_col is not None
    
    rows_with_low_error = 0
    spatial_range = 0.0
    joint_span = 0.0
    
    # Calculate spatial diversity (XY bounding box diagonal)
    if has_positions:
        xs, ys = [], []
        for r in rows:
            try:
                xs.append(float(r[x_col]))
                ys.append(float(r[y_col]))
            except: pass
        if xs and ys:
            x_range = max(xs) - min(xs)
            y_range = max(ys) - min(ys)
            spatial_range = math.sqrt(x_range**2 + y_range**2)
            
    # Count rows with low error (< 5.0 mm)
    if has_error:
        for r in rows:
            try:
                if float(r[err_col]) < 5.0:
                    rows_with_low_error += 1
            except: pass

    # Estimate joint span (max across j0, j1, j2 columns)
    for j_cand in ['j0_deg', 'j1_deg', 'j2_deg', 'j0', 'j1', 'j2', 'joint0', 'joint1', 'joint2']:
        j_col = find_col(headers, [j_cand])
        if j_col:
            try:
                vals = [float(r[j_col]) for r in rows if str(r.get(j_col, '')).strip()]
                if vals:
                    span = max(vals) - min(vals)
                    joint_span = max(joint_span, span)
            except: pass

    print(json.dumps({
        "has_positions": has_positions, 
        "has_error": has_error, 
        "rows_with_low_error": rows_with_low_error, 
        "spatial_range_m": spatial_range,
        "joint_span_deg": joint_span
    }))
except Exception as e:
    print(json.dumps({
        "has_positions": False, "has_error": False, "rows_with_low_error": 0, 
        "spatial_range_m": 0.0, "joint_span_deg": 0.0, "error": str(e)
    }))
PYEOF
    )
fi

# 3. Check JSON
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_configs": 0, "dof": 0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['dof', 'link_lengths_m', 'total_configs_tested', 'max_fk_error_mm', 'mean_fk_error_mm', 'joint_handles_created']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields, 
        'total_configs': int(d.get('total_configs_tested', 0)),
        'dof': int(d.get('dof', 0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_configs': 0, 'dof': 0}))
" 2>/dev/null || echo '{"has_fields": false, "total_configs": 0, "dof": 0}')
fi

cat > /tmp/kinematic_chain_build_result.json << EOF
{
    "task_start": $TASK_START,
    "zmq_analysis": $ZMQ_ANALYSIS,
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