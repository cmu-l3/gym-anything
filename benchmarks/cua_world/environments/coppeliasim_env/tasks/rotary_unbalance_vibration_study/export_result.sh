#!/bin/bash
echo "=== Exporting rotary_unbalance_vibration_study Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/rotary_unbalance_vibration_study_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/vibration_sweep.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/resonance_report.json"

take_screenshot /tmp/rotary_unbalance_vibration_study_end_screenshot.png

# 1. Analyze CSV
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_columns": false, "has_resonance_peak": false, "max_amplitude": 0.0, "min_amplitude": 0.0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

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
    with open('/home/ga/Documents/CoppeliaSim/exports/vibration_sweep.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_columns": False, "has_resonance_peak": False, "max_amplitude": 0.0, "min_amplitude": 0.0}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    w_col = find_col(headers, ['omega_rad_s','omega','rad_s','freq','frequency'])
    a_col = find_col(headers, ['amplitude_m','amplitude','amp_m','amp','displacement'])
    
    has_cols = w_col is not None and a_col is not None
    has_peak = False
    max_a = 0.0
    min_a = 0.0
    
    if has_cols:
        data = []
        for r in rows:
            try:
                w = float(r[w_col])
                a = float(r[a_col])
                data.append((w, a))
            except:
                pass
        
        if data:
            data.sort(key=lambda x: x[0])  # Sort by frequency
            amps = [x[1] for x in data]
            max_a = max(amps)
            min_a = min(amps)
            
            if len(amps) >= 5:
                # Check for a resonance peak: max amplitude should be meaningfully higher 
                # than the amplitudes at the lowest and highest frequencies tested
                first_a = sum(amps[:2]) / 2.0
                last_a = sum(amps[-2:]) / 2.0
                
                # Resonance means the middle peaks higher than the ends
                if max_a > first_a * 1.1 and max_a > last_a * 1.1 and max_a > 1e-6:
                    has_peak = True

    print(json.dumps({
        "has_columns": has_cols, 
        "has_resonance_peak": has_peak, 
        "max_amplitude": max_a, 
        "min_amplitude": min_a
    }))
except Exception as e:
    print(json.dumps({"has_columns": False, "has_resonance_peak": False, "max_amplitude": 0.0, "min_amplitude": 0.0, "error": str(e)}))
PYEOF
    )
fi

# 2. Analyze JSON
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_sweep_steps": 0, "resonant_omega": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_sweep_steps','k_stiffness_n_m','m_total_kg','resonant_omega_rad_s','max_amplitude_m']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields, 
        'total_sweep_steps': int(d.get('total_sweep_steps',0)), 
        'resonant_omega': float(d.get('resonant_omega_rad_s',0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_sweep_steps': 0, 'resonant_omega': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "total_sweep_steps": 0, "resonant_omega": 0.0}')
fi

# 3. Query ZMQ API for scene state
echo "Querying ZMQ API to verify mechanism construction..."
API_CHECK=$(timeout 15 python3 << 'PYEOF'
import sys, json
sys.path.insert(0, '/opt/CoppeliaSim/programming/zmqRemoteApi/clients/python')
try:
    from coppeliasim_zmqremoteapi_client import RemoteAPIClient
    client = RemoteAPIClient('localhost', 23000)
    sim = client.require('sim')
    
    # Query all joints and shapes
    joints = sim.getObjectsInTree(sim.handle_scene, sim.object_joint_type, 0)
    shapes = sim.getObjectsInTree(sim.handle_scene, sim.object_shape_type, 0)
    
    prismatic_count = 0
    revolute_count = 0
    dynamic_shape_count = 0
    
    for j in joints:
        t = sim.getJointType(j)
        if t == sim.joint_prismatic_subtype: 
            prismatic_count += 1
        elif t == sim.joint_revolute_subtype: 
            revolute_count += 1
            
    for s in shapes:
        # Check if shape is dynamic (static param == 0)
        if sim.getObjectInt32Param(s, sim.shapeintparam_static) == 0:
            dynamic_shape_count += 1
            
    print(json.dumps({
        "api_connected": True,
        "prismatic_joints": prismatic_count,
        "revolute_joints": revolute_count,
        "dynamic_shapes": dynamic_shape_count
    }))
except Exception as e:
    print(json.dumps({"api_connected": False, "error": str(e), "prismatic_joints": 0, "revolute_joints": 0, "dynamic_shapes": 0}))
PYEOF
) || echo '{"api_connected": false, "error": "timeout", "prismatic_joints": 0, "revolute_joints": 0, "dynamic_shapes": 0}'

# Fallback if timeout happens
if [ -z "$API_CHECK" ]; then
    API_CHECK='{"api_connected": false, "prismatic_joints": 0, "revolute_joints": 0, "dynamic_shapes": 0}'
fi

# Write result JSON
cat > /tmp/vibration_study_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS,
    "api_check": $API_CHECK
}
EOF

echo "=== Export Complete ==="