#!/bin/bash
echo "=== Exporting payload_com_identification Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/payload_com_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/ft_measurements.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/payload_identification.json"

take_screenshot /tmp/payload_com_end_screenshot.png

# 1. Process CSV Data
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ANALYSIS='{"has_cols": false, "row_count": 0, "f_mag_mean": 0.0, "fx_range": 0.0, "fy_range": 0.0, "fz_range": 0.0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, math, sys

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/ft_measurements.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_cols": False, "row_count": 0, "f_mag_mean": 0.0, "fx_range": 0.0, "fy_range": 0.0, "fz_range": 0.0}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    fx_col = find_col(headers, ['fx_n', 'fx', 'force_x'])
    fy_col = find_col(headers, ['fy_n', 'fy', 'force_y'])
    fz_col = find_col(headers, ['fz_n', 'fz', 'force_z'])
    tx_col = find_col(headers, ['tx_nm', 'tx', 'torque_x'])
    
    has_cols = all([fx_col, fy_col, fz_col, tx_col])
    
    if has_cols:
        fxs = [float(r[fx_col]) for r in rows if str(r.get(fx_col,'')).strip()]
        fys = [float(r[fy_col]) for r in rows if str(r.get(fy_col,'')).strip()]
        fzs = [float(r[fz_col]) for r in rows if str(r.get(fz_col,'')).strip()]
        
        if len(fxs) > 0 and len(fys) > 0 and len(fzs) > 0:
            f_mags = [math.sqrt(x**2 + y**2 + z**2) for x,y,z in zip(fxs, fys, fzs)]
            f_mag_mean = sum(f_mags) / len(f_mags)
            fx_range = max(fxs) - min(fxs)
            fy_range = max(fys) - min(fys)
            fz_range = max(fzs) - min(fzs)
        else:
            f_mag_mean, fx_range, fy_range, fz_range = 0.0, 0.0, 0.0, 0.0
    else:
        f_mag_mean, fx_range, fy_range, fz_range = 0.0, 0.0, 0.0, 0.0

    print(json.dumps({
        "has_cols": has_cols,
        "row_count": len(rows),
        "f_mag_mean": f_mag_mean,
        "fx_range": fx_range,
        "fy_range": fy_range,
        "fz_range": fz_range
    }))
except Exception as e:
    print(json.dumps({"has_cols": False, "row_count": 0, "error": str(e)}))
PYEOF
    )
fi

# 2. Process JSON Report
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_INFO='{"has_fields": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_INFO=$(python3 << 'PYEOF'
import json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/payload_identification.json') as f:
        d = json.load(f)
    req = ['total_orientations', 'true_mass_kg', 'true_com_x_m', 'true_com_y_m', 'true_com_z_m', 
           'estimated_mass_kg', 'estimated_com_x_m', 'estimated_com_y_m', 'estimated_com_z_m']
    has_fields = all(k in d for k in req)
    
    print(json.dumps({
        "has_fields": has_fields,
        "total_orientations": int(d.get('total_orientations', 0)),
        "true_mass_kg": float(d.get('true_mass_kg', 0.0)),
        "estimated_mass_kg": float(d.get('estimated_mass_kg', 0.0)),
        "true_com_x": float(d.get('true_com_x_m', 0.0)),
        "true_com_y": float(d.get('true_com_y_m', 0.0)),
        "true_com_z": float(d.get('true_com_z_m', 0.0)),
        "est_com_x": float(d.get('estimated_com_x_m', 0.0)),
        "est_com_y": float(d.get('estimated_com_y_m', 0.0)),
        "est_com_z": float(d.get('estimated_com_z_m', 0.0))
    }))
except Exception as e:
    print(json.dumps({"has_fields": False, "error": str(e)}))
PYEOF
    )
fi

# 3. Create combined result payload
cat > /tmp/payload_com_result.json << EOF
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