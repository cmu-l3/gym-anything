#!/bin/bash
echo "=== Exporting energy_consumption_profiling Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/energy_consumption_profiling_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/energy_profile.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/energy_report.json"

# Take final screenshot
take_screenshot /tmp/energy_consumption_profiling_end_screenshot.png

# Check CSV file
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    # Extract CSV stats using Python
    CSV_STATS=$(python3 << 'PYEOF'
import csv, sys, json

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/energy_profile.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    if not rows:
        print(json.dumps({"row_count": 0, "has_required_cols": False, "unique_profiles": 0, "valid_power_rows": 0}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    
    # Flexible column names
    prof_col = find_col(headers, ['profile_id', 'profile', 'motion_id', 'motion_profile'])
    pow_col = find_col(headers, ['power_w', 'power', 'instantaneous_power', 'power_watts'])
    
    has_required_cols = prof_col is not None and pow_col is not None
    
    unique_profiles = set()
    valid_power_rows = 0
    
    if has_required_cols:
        for r in rows:
            prof = r.get(prof_col, "").strip()
            if prof:
                unique_profiles.add(prof)
            try:
                p = float(r.get(pow_col, -1))
                if p >= 0:  # Power should be non-negative (|torque x velocity|)
                    valid_power_rows += 1
            except:
                pass
                
    print(json.dumps({
        "row_count": len(rows),
        "has_required_cols": has_required_cols,
        "unique_profiles": len(unique_profiles),
        "valid_power_rows": valid_power_rows
    }))
except Exception as e:
    print(json.dumps({"row_count": 0, "has_required_cols": False, "unique_profiles": 0, "valid_power_rows": 0, "error": str(e)}))
PYEOF
    )
    
    # Extract row count to bash variable for easy access
    CSV_ROW_COUNT=$(echo "$CSV_STATS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('row_count', 0))" 2>/dev/null || echo "0")
else
    CSV_STATS='{"row_count": 0, "has_required_cols": false, "unique_profiles": 0, "valid_power_rows": 0}'
fi

# Check JSON report file
JSON_EXISTS=false
JSON_IS_NEW=false

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
    required = ['total_profiles', 'total_samples', 'total_energy_J', 'peak_power_W', 'avg_power_W', 'energy_per_profile']
    has_fields = all(k in data for k in required)
    
    total_profiles = int(data.get('total_profiles', 0))
    total_energy = float(data.get('total_energy_J', 0))
    peak_power = float(data.get('peak_power_W', 0))
    
    epp = data.get('energy_per_profile', {})
    valid_epp = isinstance(epp, dict) and len(epp) >= 3 and all(float(v) > 0 for v in epp.values())
    
    print(json.dumps({
        'has_fields': has_fields, 
        'total_profiles': total_profiles, 
        'total_energy': total_energy,
        'peak_power': peak_power,
        'valid_epp': valid_epp
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_profiles': 0, 'total_energy': 0.0, 'peak_power': 0.0, 'valid_epp': False}))
" 2>/dev/null || echo '{"has_fields": false, "total_profiles": 0, "total_energy": 0.0, "peak_power": 0.0, "valid_epp": false}')
else
    JSON_INFO='{"has_fields": false, "total_profiles": 0, "total_energy": 0.0, "peak_power": 0.0, "valid_epp": false}'
fi

# Write result JSON
cat > /tmp/energy_consumption_profiling_result.json << EOF
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