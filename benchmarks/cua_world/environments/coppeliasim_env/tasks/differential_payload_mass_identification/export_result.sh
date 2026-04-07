#!/bin/bash
echo "=== Exporting differential_payload_mass_identification Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/payload_mass_identification_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/torque_data.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/payload_estimation.json"

take_screenshot /tmp/payload_mass_identification_end_screenshot.png

# Initialize variables
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_required_cols": false, "r_value": 0.0, "regression_slope": 0.0, "valid_rows": 0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW=true
    fi

    # Execute Python analysis to extract correlation and slope
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, math, sys

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/torque_data.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"has_required_cols": False, "r_value": 0.0, "regression_slope": 0.0, "valid_rows": 0}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    
    # Locate required columns flexibly
    reach_col = find_col(headers, ['reach_m', 'reach', 'horizontal_reach', 'lever_arm'])
    dtau_col = find_col(headers, ['delta_torque', 'd_torque', 'torque_diff', 'dtau'])
    
    has_cols = reach_col is not None and dtau_col is not None
    
    if has_cols:
        reach_vals = []
        dtau_vals = []
        for r in rows:
            try:
                # Use absolute values to avoid sign issues based on axis definition
                rv = abs(float(r[reach_col]))
                tv = abs(float(r[dtau_col]))
                reach_vals.append(rv)
                dtau_vals.append(tv)
            except:
                pass
                
        n = len(reach_vals)
        
        # Calculate Pearson correlation coefficient and linear slope
        if n >= 2:
            sum_x = sum(reach_vals)
            sum_y = sum(dtau_vals)
            sum_x2 = sum(x*x for x in reach_vals)
            sum_y2 = sum(y*y for y in dtau_vals)
            sum_xy = sum(x*y for x, y in zip(reach_vals, dtau_vals))
            
            denom = math.sqrt((n * sum_x2 - sum_x**2) * (n * sum_y2 - sum_y**2))
            if denom == 0:
                r_val = 0.0
            else:
                r_val = (n * sum_xy - sum_x * sum_y) / denom
                
            variance_x = n * sum_x2 - sum_x**2
            if variance_x == 0:
                slope = 0.0
            else:
                slope = (n * sum_xy - sum_x * sum_y) / variance_x
        else:
            r_val = 0.0
            slope = 0.0
            
        print(json.dumps({
            "has_required_cols": True,
            "r_value": r_val,
            "regression_slope": slope,
            "valid_rows": n
        }))
    else:
        print(json.dumps({"has_required_cols": False, "r_value": 0.0, "regression_slope": 0.0, "valid_rows": 0}))
        
except Exception as e:
    print(json.dumps({"has_required_cols": False, "r_value": 0.0, "regression_slope": 0.0, "valid_rows": 0, "error": str(e)}))
PYEOF
    )
    
    # Extract row count directly
    CSV_ROW_COUNT=$(python3 -c "import json; print(json.loads('''$CSV_ANALYSIS''').get('valid_rows', 0))" 2>/dev/null || echo "0")
fi


JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_configs": 0, "estimated_mass_kg": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW=true
    fi
    
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_configs', 'analyzed_joint_name', 'estimated_mass_kg']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields, 
        'total_configs': int(d.get('total_configs', 0)), 
        'estimated_mass_kg': float(d.get('estimated_mass_kg', 0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_configs': 0, 'estimated_mass_kg': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "total_configs": 0, "estimated_mass_kg": 0.0}')
fi

# Write summary JSON for the verifier
cat > /tmp/payload_mass_identification_result.json << EOF
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