#!/bin/bash
echo "=== Exporting agv_payload_stability_study Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/agv_payload_stability_study_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/stability_trials.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/stability_report.json"

# Take final screenshot
take_screenshot /tmp/agv_payload_stability_study_end_screenshot.png

# 1. Analyze CSV
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_STATS='{"row_count": 0, "has_req_cols": false, "has_true": false, "has_false": false, "min_accel": 0.0, "max_accel": 0.0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_STATS=$(python3 << 'PYEOF'
import csv, json, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/stability_trials.csv', 'r') as f:
        reader = list(csv.DictReader(f))
        
    if not reader:
        print(json.dumps({"row_count": 0, "has_req_cols": False, "has_true": False, "has_false": False, "min_accel": 0.0, "max_accel": 0.0}))
        sys.exit(0)
        
    headers = [h.strip().lower() for h in reader[0].keys()]
    
    # Check for required columns
    req_cols = ['acceleration_m_s2', 'tipped']
    has_req_cols = all(any(c in h for h in headers) for c in req_cols)
    
    # Find exact column names used
    accel_col = next((h for h in reader[0].keys() if 'accel' in h.lower()), None)
    tipped_col = next((h for h in reader[0].keys() if 'tip' in h.lower()), None)
    
    has_true = False
    has_false = False
    accels = []
    
    if accel_col and tipped_col:
        for r in reader:
            # Parse tipped boolean
            val = str(r.get(tipped_col, '')).strip().lower()
            is_tipped = val in ['true', '1', 'yes', 't', 'y']
            if is_tipped:
                has_true = True
            else:
                has_false = True
                
            # Parse acceleration
            try:
                accels.append(float(r.get(accel_col, 0)))
            except ValueError:
                pass

    print(json.dumps({
        "row_count": len(reader),
        "has_req_cols": has_req_cols,
        "has_true": has_true,
        "has_false": has_false,
        "min_accel": min(accels) if accels else 0.0,
        "max_accel": max(accels) if accels else 0.0
    }))
except Exception as e:
    print(json.dumps({"row_count": 0, "has_req_cols": False, "has_true": False, "has_false": False, "min_accel": 0.0, "max_accel": 0.0, "error": str(e)}))
PYEOF
    )
fi

# 2. Analyze JSON
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_INFO='{"has_fields": false, "total_trials": 0, "max_safe": 0.0, "min_tipping": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
        
    required = ['total_trials', 'max_safe_acceleration_m_s2', 'min_tipping_acceleration_m_s2']
    has_fields = all(k in data for k in required)
    
    total = int(data.get('total_trials', 0))
    max_safe = float(data.get('max_safe_acceleration_m_s2', 0.0))
    min_tipping = float(data.get('min_tipping_acceleration_m_s2', 0.0))
    
    print(json.dumps({
        'has_fields': has_fields,
        'total_trials': total,
        'max_safe': max_safe,
        'min_tipping': min_tipping
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_trials': 0, 'max_safe': 0.0, 'min_tipping': 0.0, 'error': str(e)}))
" 2>/dev/null || echo '{"has_fields": false, "total_trials": 0, "max_safe": 0.0, "min_tipping": 0.0}')
fi

# 3. Write final unified result JSON
cat > /tmp/agv_payload_stability_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_stats": $CSV_STATS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_info": $JSON_INFO
}
EOF

echo "=== Export Complete ==="