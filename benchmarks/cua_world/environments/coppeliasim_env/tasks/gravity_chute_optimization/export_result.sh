#!/bin/bash
echo "=== Exporting gravity_chute_optimization Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/gravity_chute_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/chute_kinematics.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/chute_optimization.json"

take_screenshot /tmp/gravity_chute_end_screenshot.png

CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ANALYSIS='{"valid": false, "rows": 0, "data_extracted": 0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/chute_kinematics.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"valid": False, "rows": 0, "data_extracted": 0}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    angle_col = find_col(headers, ['angle_deg', 'angle', 'tilt_angle'])
    vel_col = find_col(headers, ['exit_vel_m_s', 'velocity', 'exit_velocity', 'vel'])
    
    valid = angle_col is not None and vel_col is not None
    data = []
    
    if valid:
        for r in rows:
            try:
                data.append({
                    'angle': float(r[angle_col]),
                    'vel': float(r[vel_col])
                })
            except:
                pass
                
    # Sort data by angle to check physics consistency
    data.sort(key=lambda x: x['angle'])
    angles = [d['angle'] for d in data]
    vels = [d['vel'] for d in data]
    
    # Compute which angle was theoretically best (closest to 1.5 m/s)
    computed_best_angle = None
    if data:
        best_match = min(data, key=lambda x: abs(x['vel'] - 1.5))
        computed_best_angle = best_match['angle']

    print(json.dumps({
        "valid": valid,
        "rows": len(rows),
        "data_extracted": len(data),
        "angles": angles,
        "vels": vels,
        "computed_best_angle": computed_best_angle
    }))
except Exception as e:
    print(json.dumps({"valid": False, "rows": 0, "data_extracted": 0, "error": str(e)}))
PYEOF
    )
fi

JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_ANALYSIS='{"valid": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi

    JSON_ANALYSIS=$(python3 << 'PYEOF'
import json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/chute_optimization.json') as f:
        d = json.load(f)
    req = ['total_angles_tested', 'target_velocity_m_s', 'optimal_angle_deg']
    has_fields = all(k in d for k in req)
    
    optimal_angle = float(d.get('optimal_angle_deg', -999))
    total_angles = int(d.get('total_angles_tested', 0))
    
    print(json.dumps({
        "valid": has_fields,
        "optimal_angle_deg": optimal_angle,
        "total_angles_tested": total_angles
    }))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# Package all verification data
TEMP_JSON=$(mktemp /tmp/gravity_chute_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
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

rm -f /tmp/gravity_chute_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/gravity_chute_result.json
chmod 666 /tmp/gravity_chute_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="