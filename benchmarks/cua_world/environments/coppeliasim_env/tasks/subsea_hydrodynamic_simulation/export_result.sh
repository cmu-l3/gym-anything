#!/bin/bash
echo "=== Exporting subsea_hydrodynamic_simulation Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/hydrodynamics.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/hydrodynamics_report.json"

# Take final screenshot as evidence
take_screenshot /tmp/task_end_screenshot.png

# Analyze CSV
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ANALYSIS='{"has_req_cols": false, "rows_A": 0, "rows_B": 0, "rows_C": 0, "transient_consistent": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys

def get_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/hydrodynamics.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    if not rows:
        print(json.dumps({"has_req_cols": False, "rows_A": 0, "rows_B": 0, "rows_C": 0, "transient_consistent": False}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    cid_col = get_col(headers, ['config_id', 'config', 'id'])
    t_col = get_col(headers, ['time_s', 'time'])
    vz_col = get_col(headers, ['z_vel_ms', 'vel_z', 'vz', 'z_velocity'])
    fz_col = get_col(headers, ['applied_force_z_n', 'force_z', 'fz', 'applied_force_z', 'applied_force'])
    
    has_req_cols = all(c is not None for c in [cid_col, t_col, vz_col, fz_col])
    
    rows_A, rows_B, rows_C = 0, 0, 0
    transient_consistent = False
    
    if has_req_cols:
        vA, vB, vC = [], [], []
        for r in rows:
            c = str(r[cid_col]).strip().upper()
            try:
                v = float(r[vz_col])
                if c == 'A' or 'A' in c: vA.append(v)
                elif c == 'B' or 'B' in c: vB.append(v)
                elif c == 'C' or 'C' in c: vC.append(v)
            except:
                pass
        
        rows_A, rows_B, rows_C = len(vA), len(vB), len(vC)
        
        # Check transient consistency: Velocity shouldn't be constant.
        # Should start near 0 and accelerate to a terminal velocity
        def is_transient(v_arr):
            if len(v_arr) < 20: return False
            start_v = abs(v_arr[0])
            end_v = abs(v_arr[-1])
            # Starts low, ends high, with significant delta indicating curve
            return start_v < 1.0 and end_v > 1.0 and abs(end_v - start_v) > 0.5
            
        transient_consistent = is_transient(vA) or is_transient(vB) or is_transient(vC)
        
    print(json.dumps({
        "has_req_cols": has_req_cols,
        "rows_A": rows_A,
        "rows_B": rows_B,
        "rows_C": rows_C,
        "transient_consistent": transient_consistent
    }))
except Exception as e:
    print(json.dumps({"has_req_cols": False, "rows_A": 0, "rows_B": 0, "rows_C": 0, "transient_consistent": False, "error": str(e)}))
PYEOF
    )
fi

# Analyze JSON
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_configs": 0, "term_v_A": 0.0, "term_v_B": 0.0, "term_v_C": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_configs', 'terminal_velocity_A', 'terminal_velocity_B', 'terminal_velocity_C']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'total_configs': int(d.get('total_configs',0)),
        'term_v_A': float(d.get('terminal_velocity_A',0.0)),
        'term_v_B': float(d.get('terminal_velocity_B',0.0)),
        'term_v_C': float(d.get('terminal_velocity_C',0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_configs': 0, 'term_v_A': 0.0, 'term_v_B': 0.0, 'term_v_C': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "total_configs": 0, "term_v_A": 0.0, "term_v_B": 0.0, "term_v_C": 0.0}')
fi

# Write results
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS
}
EOF

echo "=== Export Complete ==="