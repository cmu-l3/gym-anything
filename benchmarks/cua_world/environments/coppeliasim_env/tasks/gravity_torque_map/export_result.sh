#!/bin/bash
echo "=== Exporting gravity_torque_map Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/gravity_torque_map_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/torque_map.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/torque_report.json"

# Take final screenshot
take_screenshot /tmp/gravity_torque_map_end_screenshot.png

# Check CSV file and analyze physics plausibility
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ANALYSIS='{"valid": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math
import statistics

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/torque_map.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"valid": False, "error": "Empty CSV"}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    s_deg_col = find_col(headers, ['shoulder_deg', 'shoulder_angle'])
    e_deg_col = find_col(headers, ['elbow_deg', 'elbow_angle'])
    s_tor_col = find_col(headers, ['shoulder_torque_nm', 'shoulder_torque'])
    e_tor_col = find_col(headers, ['elbow_torque_nm', 'elbow_torque'])
    
    if not (s_deg_col and e_deg_col and s_tor_col and e_tor_col):
        print(json.dumps({"valid": False, "error": "Missing required columns"}))
        sys.exit(0)
        
    s_degs = [float(r[s_deg_col]) for r in rows if r.get(s_deg_col, '').strip()]
    e_degs = [float(r[e_deg_col]) for r in rows if r.get(e_deg_col, '').strip()]
    s_tors = [abs(float(r[s_tor_col])) for r in rows if r.get(s_tor_col, '').strip()]
    e_tors = [abs(float(r[e_tor_col])) for r in rows if r.get(e_tor_col, '').strip()]
    
    unique_s = len(set([round(x, 1) for x in s_degs]))
    unique_e = len(set([round(x, 1) for x in e_degs]))
    span_s = max(s_degs) - min(s_degs) if s_degs else 0
    span_e = max(e_degs) - min(e_degs) if e_degs else 0
    max_s_tor = max(s_tors) if s_tors else 0
    max_e_tor = max(e_tors) if e_tors else 0
    std_s_tor = statistics.stdev(s_tors) if len(s_tors) > 1 else 0
    
    print(json.dumps({
        "valid": True,
        "row_count": len(rows),
        "unique_s": unique_s,
        "unique_e": unique_e,
        "span_s": span_s,
        "span_e": span_e,
        "max_s_tor": max_s_tor,
        "max_e_tor": max_e_tor,
        "std_s_tor": std_s_tor
    }))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# Check JSON report
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_ANALYSIS='{"valid": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    
    JSON_ANALYSIS=$(python3 << 'PYEOF'
import json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/torque_report.json') as f:
        data = json.load(f)
    print(json.dumps({
        "valid": True,
        "total_configs": int(data.get("total_configs", 0)),
        "max_s_tor": float(data.get("max_shoulder_torque_nm", 0)),
        "max_e_tor": float(data.get("max_elbow_torque_nm", 0))
    }))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# Write combined result JSON
cat > /tmp/gravity_torque_map_result.json << EOF
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

echo "=== Export Complete ==="