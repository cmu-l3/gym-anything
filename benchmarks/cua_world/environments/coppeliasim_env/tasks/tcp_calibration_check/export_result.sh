#!/bin/bash
echo "=== Exporting tcp_calibration_check Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/tcp_calibration_check_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/tcp_scatter.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/tcp_report.json"

# Take final screenshot
take_screenshot /tmp/tcp_calibration_check_end_screenshot.png

# ==============================================================================
# CSV Analysis
# ==============================================================================
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_positions": false, "in_bounds": false, "diverse_joints_count": 0, "max_joint_ranges": []}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    # Row count (excluding header)
    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        print(len(list(csv.DictReader(f))))
except:
    print(0)
" 2>/dev/null || echo "0")

    # Analyze CSV content
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/tcp_scatter.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"has_positions": False, "in_bounds": False, "diverse_joints_count": 0, "max_joint_ranges": []}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    
    # Position columns
    px = find_col(headers, ['measured_x','actual_x','x_m','x'])
    py = find_col(headers, ['measured_y','actual_y','y_m','y'])
    pz = find_col(headers, ['measured_z','actual_z','z_m','z'])
    
    has_positions = px is not None and py is not None and pz is not None
    in_bounds = True
    valid_pos_count = 0
    
    if has_positions:
        for r in rows:
            try:
                vx, vy, vz = float(r[px]), float(r[py]), float(r[pz])
                valid_pos_count += 1
                # Check workspace plausibility (+/- 3.0 meters)
                if abs(vx) > 3.0 or abs(vy) > 3.0 or abs(vz) > 3.0:
                    in_bounds = False
            except:
                pass
        if valid_pos_count < len(rows) * 0.5:
            in_bounds = False # Too many invalid floats
    else:
        in_bounds = False
        
    # Joint variation analysis
    joint_ranges = []
    # Test up to 6 joints
    for j_idx in range(6):
        candidates = [f'j{j_idx}_deg', f'j{j_idx}', f'q{j_idx}', f'joint{j_idx}', f'joint_{j_idx}']
        j_col = find_col(headers, candidates)
        if j_col:
            try:
                vals = [float(r[j_col]) for r in rows if r.get(j_col,'').strip()]
                if vals:
                    j_range = max(vals) - min(vals)
                    joint_ranges.append(j_range)
            except:
                pass
                
    # Sort joint ranges descending
    joint_ranges.sort(reverse=True)
    # How many joints varied by >= 20 degrees?
    diverse_joints_count = sum(1 for r in joint_ranges if r >= 20.0)
    
    print(json.dumps({
        "has_positions": has_positions, 
        "in_bounds": in_bounds, 
        "diverse_joints_count": diverse_joints_count, 
        "max_joint_ranges": joint_ranges[:3]
    }))
except Exception as e:
    print(json.dumps({"has_positions": False, "in_bounds": False, "diverse_joints_count": 0, "max_joint_ranges": [], "error": str(e)}))
PYEOF
    )
fi

# ==============================================================================
# JSON Analysis
# ==============================================================================
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_FIELDS='{"has_fields": false, "total_orientations": 0, "max_deviation_mm": -1.0, "scatter_sphere_radius_mm": -1.0, "valid_std": false}'

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
        
    req = ['total_orientations', 'mean_x', 'mean_y', 'mean_z', 'std_x_mm', 'std_y_mm', 'std_z_mm', 'max_deviation_mm', 'scatter_sphere_radius_mm']
    has_fields = all(k in d for k in req)
    
    total = int(d.get('total_orientations', 0))
    max_dev = float(d.get('max_deviation_mm', -1.0))
    scatter = float(d.get('scatter_sphere_radius_mm', -1.0))
    
    sx = float(d.get('std_x_mm', -1.0))
    sy = float(d.get('std_y_mm', -1.0))
    sz = float(d.get('std_z_mm', -1.0))
    valid_std = sx >= 0 and sy >= 0 and sz >= 0
    
    print(json.dumps({
        'has_fields': has_fields, 
        'total_orientations': total, 
        'max_deviation_mm': max_dev,
        'scatter_sphere_radius_mm': scatter,
        'valid_std': valid_std
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_orientations': 0, 'max_deviation_mm': -1.0, 'scatter_sphere_radius_mm': -1.0, 'valid_std': False}))
" 2>/dev/null || echo '{"has_fields": false, "total_orientations": 0, "max_deviation_mm": -1.0, "scatter_sphere_radius_mm": -1.0, "valid_std": false}')
fi

# Write results
cat > /tmp/tcp_calibration_check_result.json << EOF
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

# Ensure verifier can read it
chmod 666 /tmp/tcp_calibration_check_result.json 2>/dev/null || sudo chmod 666 /tmp/tcp_calibration_check_result.json 2>/dev/null || true

echo "=== Export Complete ==="