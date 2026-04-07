#!/bin/bash
echo "=== Exporting robot_cable_routing_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/robot_cable_routing_analysis_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/cable_measurements.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/cable_report.json"

# Take final screenshot
take_screenshot /tmp/robot_cable_routing_analysis_end_screenshot.png

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_cols": false, "valid_math": false, "max_error": 999.0, "variance": 0.0}'

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

    # Run Python script to strictly validate the coordinate distances and variance
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, math, sys

def calc_dist(p1, p2):
    return math.sqrt(sum((a - b)**2 for a, b in zip(p1, p2)))

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/cable_measurements.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"has_cols": False, "valid_math": False, "max_error": 999.0, "variance": 0.0}))
        sys.exit(0)
        
    headers = [h.strip() for h in rows[0].keys()]
    req_cols = ['t0_x', 't0_y', 't0_z', 't1_x', 't1_y', 't1_z', 't2_x', 't2_y', 't2_z', 't3_x', 't3_y', 't3_z', 
                'segment1_m', 'segment2_m', 'segment3_m', 'total_length_m']
    
    if not all(c in headers for c in req_cols):
        print(json.dumps({"has_cols": False, "valid_math": False, "max_error": 999.0, "variance": 0.0}))
        sys.exit(0)
        
    max_err = 0.0
    lengths = []
    
    for r in rows:
        try:
            t0 = (float(r['t0_x']), float(r['t0_y']), float(r['t0_z']))
            t1 = (float(r['t1_x']), float(r['t1_y']), float(r['t1_z']))
            t2 = (float(r['t2_x']), float(r['t2_y']), float(r['t2_z']))
            t3 = (float(r['t3_x']), float(r['t3_y']), float(r['t3_z']))
            
            s1 = float(r['segment1_m'])
            s2 = float(r['segment2_m'])
            s3 = float(r['segment3_m'])
            tot = float(r['total_length_m'])
            
            c_s1 = calc_dist(t0, t1)
            c_s2 = calc_dist(t1, t2)
            c_s3 = calc_dist(t2, t3)
            c_tot = c_s1 + c_s2 + c_s3
            
            err1 = abs(s1 - c_s1)
            err2 = abs(s2 - c_s2)
            err3 = abs(s3 - c_s3)
            err_tot = abs(tot - c_tot)
            
            max_err = max(max_err, err1, err2, err3, err_tot)
            lengths.append(tot)
        except Exception:
            max_err = 999.0
            break
            
    variance = max(lengths) - min(lengths) if lengths else 0.0
    valid_math = max_err < 1e-3  # Allowance for floating point truncation
    
    print(json.dumps({"has_cols": True, "valid_math": valid_math, "max_error": max_err, "variance": variance}))
except Exception as e:
    print(json.dumps({"has_cols": False, "valid_math": False, "max_error": 999.0, "variance": 0.0, "error": str(e)}))
PYEOF
    )
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_configs": 0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    
    JSON_FIELDS=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_configs', 'min_length_m', 'max_length_m', 'variance_m', 'recommended_length_m']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'total_configs': int(d.get('total_configs', 0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_configs': 0}))
" 2>/dev/null || echo '{"has_fields": false, "total_configs": 0}')
fi

cat > /tmp/robot_cable_routing_analysis_result.json << EOF
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