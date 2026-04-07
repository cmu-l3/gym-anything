#!/bin/bash
echo "=== Exporting trajectory_clearance_audit Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/clearance_audit_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/clearance_audit.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/audit_summary.json"
TTT="/home/ga/Documents/CoppeliaSim/exports/audit_scene.ttt"

# Take final screenshot
take_screenshot /tmp/clearance_audit_end_screenshot.png

# 1. Check TTT Scene Artifact
TTT_EXISTS=false
TTT_IS_NEW=false
TTT_SIZE=0

if [ -f "$TTT" ]; then
    TTT_EXISTS=true
    TTT_MTIME=$(stat -c %Y "$TTT" 2>/dev/null || echo "0")
    [ "$TTT_MTIME" -gt "$TASK_START" ] && TTT_IS_NEW=true
    TTT_SIZE=$(stat -c %s "$TTT" 2>/dev/null || echo "0")
fi

# 2. Check CSV Trajectory File
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_STATS='{"has_clearance": false, "row_count": 0, "unique_clearances": 0, "min_clearance": 0.0, "joint_variance": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    # Python script safely parses the CSV, avoiding bash text manipulation headaches
    CSV_STATS=$(python3 << 'PYEOF'
import csv, sys, json
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/clearance_audit.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_clearance": False, "row_count": 0, "unique_clearances": 0, "min_clearance": 0.0, "joint_variance": False}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    clear_col = next((h for h in headers if 'clearance' in h.lower() or 'dist' in h.lower()), None)
    
    has_clearance = clear_col is not None
    unique_clearances = 0
    min_clearance = 0.0
    joint_variance = False
    
    if has_clearance:
        clearances = []
        for r in rows:
            try:
                val = float(r[clear_col])
                clearances.append(val)
            except:
                pass
        
        if clearances:
            min_clearance = min(clearances)
            # Rounding handles minor float deviations when counting uniqueness
            unique_clearances = len(set([round(c, 4) for c in clearances]))
            
    # Check joint variance (verify they actually swept a trajectory, not just static)
    for h in headers:
        if h != clear_col and 'step' not in h.lower() and 'id' not in h.lower():
            try:
                vals = [float(r[h]) for r in rows if r[h].strip()]
                if len(set(vals)) > 1:
                    joint_variance = True
                    break
            except:
                pass

    print(json.dumps({
        "has_clearance": has_clearance,
        "row_count": len(rows),
        "unique_clearances": unique_clearances,
        "min_clearance": min_clearance,
        "joint_variance": joint_variance
    }))
except Exception as e:
    print(json.dumps({"has_clearance": False, "row_count": 0, "unique_clearances": 0, "min_clearance": 0.0, "joint_variance": False, "error": str(e)}))
PYEOF
    )
fi

# 3. Check JSON Report File
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_INFO='{"has_fields": false, "total_steps": 0, "obstacles_evaluated": 0, "absolute_min_clearance_m": 0.0, "clearance_violation": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
    required = ['total_steps', 'obstacles_evaluated', 'absolute_min_clearance_m', 'critical_step_id', 'clearance_violation']
    has_fields = all(k in data for k in required)
    print(json.dumps({
        'has_fields': has_fields,
        'total_steps': int(data.get('total_steps', 0)),
        'obstacles_evaluated': int(data.get('obstacles_evaluated', 0)),
        'absolute_min_clearance_m': float(data.get('absolute_min_clearance_m', 0.0)),
        'clearance_violation': bool(data.get('clearance_violation', False))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_steps': 0, 'obstacles_evaluated': 0, 'absolute_min_clearance_m': 0.0, 'clearance_violation': False}))
" 2>/dev/null || echo '{"has_fields": false, "total_steps": 0, "obstacles_evaluated": 0, "absolute_min_clearance_m": 0.0, "clearance_violation": false}')
fi

# Write consolidated result JSON to temp for safe permission handling
cat > /tmp/clearance_audit_result.json << EOF
{
    "task_start": $TASK_START,
    "ttt_exists": $TTT_EXISTS,
    "ttt_is_new": $TTT_IS_NEW,
    "ttt_size_bytes": $TTT_SIZE,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_stats": $CSV_STATS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_info": $JSON_INFO
}
EOF

echo "=== Export Complete ==="