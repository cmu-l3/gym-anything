#!/bin/bash
echo "=== Exporting mobile_odometry_drift_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/odometry_drift_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/odometry_track.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/odometry_summary.json"

# Take final screenshot
take_screenshot /tmp/odometry_drift_end_screenshot.png

# Check CSV file
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ANALYSIS='{"valid": false, "reason": "Not evaluated"}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    # Run Python script to parse and analyze the CSV kinematics
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, math, sys

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/odometry_track.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"valid": False, "reason": "Empty CSV"}))
        sys.exit(0)

    headers = list(rows[0].keys())
    ox_c = find_col(headers, ['odom_x', 'odomx', 'ox'])
    oy_c = find_col(headers, ['odom_y', 'odomy', 'oy'])
    tx_c = find_col(headers, ['true_x', 'truex', 'tx', 'x'])
    ty_c = find_col(headers, ['true_y', 'truey', 'ty', 'y'])
    tt_c = find_col(headers, ['true_theta', 'truetheta', 'tt', 'theta'])
    err_c = find_col(headers, ['error_m', 'error', 'err', 'drift_error'])

    if not all([ox_c, oy_c, tx_c, ty_c, tt_c, err_c]):
        print(json.dumps({"valid": False, "reason": "Missing required columns (need odom_x/y, true_x/y/theta, error_m)"}))
        sys.exit(0)

    true_xs, true_ys, true_thetas = [], [], []
    odom_xs, odom_ys, reported_errs, calculated_errs = [], [], [], []

    for r in rows:
        try:
            tx, ty, tt = float(r[tx_c]), float(r[ty_c]), float(r[tt_c])
            ox, oy, err = float(r[ox_c]), float(r[oy_c]), float(r[err_c])
            
            true_xs.append(tx)
            true_ys.append(ty)
            true_thetas.append(tt)
            odom_xs.append(ox)
            odom_ys.append(oy)
            reported_errs.append(err)
            calculated_errs.append(math.sqrt((tx-ox)**2 + (ty-oy)**2))
        except:
            pass
            
    if len(true_xs) < 10:
        print(json.dumps({"valid": False, "reason": "Insufficient valid data rows"}))
        sys.exit(0)

    # Calculate Total Translation (path length of ground truth)
    translation = 0.0
    for i in range(1, len(true_xs)):
        translation += math.sqrt((true_xs[i]-true_xs[i-1])**2 + (true_ys[i]-true_ys[i-1])**2)

    # Calculate Total Rotation (accumulated absolute angle differences)
    rotation = 0.0
    for i in range(1, len(true_thetas)):
        diff = true_thetas[i] - true_thetas[i-1]
        # unwrap
        while diff > math.pi: diff -= 2*math.pi
        while diff < -math.pi: diff += 2*math.pi
        rotation += abs(diff)

    # Check if reported error matches calculated error (Euclidean distance)
    err_diffs = [abs(re - ce) for re, ce in zip(reported_errs, calculated_errs)]
    # Allow small floating point margin (0.05m)
    err_computation_correct = all(d < 0.05 for d in err_diffs)
    
    final_error = reported_errs[-1]
    max_error = max(reported_errs)

    print(json.dumps({
        "valid": True,
        "row_count": len(true_xs),
        "translation_m": translation,
        "rotation_rad": rotation,
        "err_computation_correct": err_computation_correct,
        "final_error_m": final_error,
        "max_error_m": max_error
    }))
except Exception as e:
    print(json.dumps({"valid": False, "reason": f"Parsing exception: {str(e)}"}))
PYEOF
    )
fi

# Check JSON report file
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_INFO='{"has_fields": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
    required = ['total_duration_s', 'total_steps', 'path_length_m', 'final_drift_error_m', 'max_drift_error_m']
    has_fields = all(k in data for k in required)
    
    print(json.dumps({
        'has_fields': has_fields,
        'path_length_m': float(data.get('path_length_m', 0.0)),
        'final_drift_error_m': float(data.get('final_drift_error_m', 0.0)),
        'max_drift_error_m': float(data.get('max_drift_error_m', 0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'error': str(e)}))
" 2>/dev/null || echo '{"has_fields": false}')
fi

# Write result JSON for the verifier
cat > /tmp/odometry_drift_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_info": $JSON_INFO
}
EOF

echo "=== Export Complete ==="