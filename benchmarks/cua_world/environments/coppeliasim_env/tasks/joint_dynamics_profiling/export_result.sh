#!/bin/bash
echo "=== Exporting joint_dynamics_profiling Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/joint_dynamics_profiling_start_ts 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/CoppeliaSim/exports/dynamics_profile.csv"
JSON_PATH="/home/ga/Documents/CoppeliaSim/exports/dynamics_report.json"

# Capture final UI state
take_screenshot /tmp/joint_dynamics_profiling_end.png

# Extract metadata & timestamps
CSV_EXISTS=false
CSV_IS_NEW=false
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW=true
    fi
fi

JSON_EXISTS=false
JSON_IS_NEW=false
if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW=true
    fi
fi

# Run comprehensive python parser to validate CSV and JSON contents safely
ANALYSIS_OUTPUT=$(python3 << 'PYEOF'
import csv, json, sys, math

result = {
    "row_count": 0, "has_req_cols": False,
    "j_ranges": [], "vel_consistent": False,
    "max_vel": 0.0, "max_acc": 0.0,
    "trajectory_duration": 0.0,
    "csv_vel_violations": 0, "csv_acc_violations": 0,
    "json_data": {}
}

# 1. Parse CSV
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/dynamics_profile.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    result["row_count"] = len(rows)
    
    if rows:
        headers = [h.strip().lower() for h in rows[0].keys()]
        
        # Check required columns
        req_cols = ['time_s']
        for i in range(6):
            req_cols.extend([f'j{i}_pos_deg', f'j{i}_vel_degs', f'j{i}_acc_degs2'])
            
        has_req_cols = all(c in headers for c in req_cols)
        result["has_req_cols"] = has_req_cols
        
        if has_req_cols:
            # Ranges
            ranges = []
            for i in range(6):
                vals = []
                for r in rows:
                    try:
                        vals.append(float(r[f'j{i}_pos_deg']))
                    except:
                        pass
                ranges.append(max(vals) - min(vals) if vals else 0.0)
            result["j_ranges"] = ranges
            
            # Duration
            try:
                times = [float(r['time_s']) for r in rows if r.get('time_s','').strip()]
                result["trajectory_duration"] = max(times) - min(times) if times else 0.0
            except:
                pass
                
            # Velocity consistency & violations
            max_v, max_a = 0.0, 0.0
            v_violations, a_violations = 0, 0
            consistent = 0
            total_checks = 0
            
            for i in range(1, len(rows)):
                try:
                    t1 = float(rows[i]['time_s'])
                    t0 = float(rows[i-1]['time_s'])
                    dt = t1 - t0
                    if dt <= 0.0001: continue
                    
                    row_v_viol = False
                    row_a_viol = False
                    
                    for j in range(6):
                        p1 = float(rows[i][f'j{j}_pos_deg'])
                        p0 = float(rows[i-1][f'j{j}_pos_deg'])
                        v_rep = float(rows[i][f'j{j}_vel_degs'])
                        a_rep = float(rows[i][f'j{j}_acc_degs2'])
                        
                        max_v = max(max_v, abs(v_rep))
                        max_a = max(max_a, abs(a_rep))
                        
                        if abs(v_rep) > 180.0: row_v_viol = True
                        if abs(a_rep) > 800.0: row_a_viol = True
                        
                        v_calc = (p1 - p0) / dt
                        # Check if calculated velocity is close to reported velocity
                        # Allow 20% tolerance or 5.0 deg/s absolute (accounting for stepping discretization)
                        if abs(v_calc - v_rep) <= max(0.2 * abs(v_calc), 5.0):
                            consistent += 1
                        total_checks += 1
                        
                    if row_v_viol: v_violations += 1
                    if row_a_viol: a_violations += 1
                except:
                    pass
                    
            result["max_vel"] = max_v
            result["max_acc"] = max_a
            result["csv_vel_violations"] = v_violations
            result["csv_acc_violations"] = a_violations
            result["vel_consistent"] = (consistent / max(1, total_checks)) > 0.7
            
except Exception as e:
    result["csv_error"] = str(e)

# 2. Parse JSON
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/dynamics_report.json') as f:
        data = json.load(f)
    result["json_data"] = data
except Exception as e:
    result["json_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# Package into a final result JSON for verifier.py
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "analysis": $ANALYSIS_OUTPUT
}
EOF

echo "Result safely exported to /tmp/task_result.json"
echo "=== Export Complete ==="