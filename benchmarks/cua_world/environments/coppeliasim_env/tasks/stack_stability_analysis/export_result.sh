#!/bin/bash
echo "=== Exporting stack_stability_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/stack_stability_analysis_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/stack_stability_data.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/stack_stability_report.json"

# Take final screenshot
take_screenshot /tmp/stack_stability_analysis_end_screenshot.png

# Check CSV file
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ANALYSIS='{"valid": false}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    # Parse CSV content using Python
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys

def get_val(row, candidates):
    for c in candidates:
        for k in row.keys():
            if k and c in k.lower().strip():
                return row[k]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/stack_stability_data.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"valid": False, "row_count": 0}))
        sys.exit(0)
        
    configs = {}
    valid_disp_count = 0
    positive_z_count = 0
    
    for r in rows:
        cid = get_val(r, ['config_id', 'config'])
        disp = get_val(r, ['max_displacement', 'displacement'])
        iz = get_val(r, ['initial_z', 'z_init', 'z'])
        
        if cid is not None and str(cid).strip() != "":
            if cid not in configs:
                configs[cid] = []
            
            # Check displacement
            try:
                d = float(disp)
                if 0 <= d <= 100:
                    valid_disp_count += 1
                    configs[cid].append(d)
            except (ValueError, TypeError):
                pass
                
            # Check initial Z (indicates objects are stacked/above ground)
            try:
                z = float(iz)
                if z > 0.01:
                    positive_z_count += 1
            except (ValueError, TypeError):
                pass
                
    num_configs = len(configs)
    has_stable = False
    has_unstable = False
    
    for cid, disps in configs.items():
        if not disps:
            continue
        if all(d < 0.05 for d in disps):
            has_stable = True
        if any(d >= 0.05 for d in disps):
            has_unstable = True

    print(json.dumps({
        "valid": True,
        "row_count": len(rows),
        "num_configs": num_configs,
        "valid_disp_count": valid_disp_count,
        "positive_z_count": positive_z_count,
        "has_stable_data": has_stable,
        "has_unstable_data": has_unstable
    }))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# Check JSON report file
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_INFO='{"has_fields": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
    req = ['total_configurations', 'stable_count', 'unstable_count']
    has_fields = all(k in data for k in req)
    
    total = int(data.get('total_configurations', 0))
    stable = int(data.get('stable_count', 0))
    unstable = int(data.get('unstable_count', 0))
    
    print(json.dumps({
        'has_fields': has_fields,
        'total_configs': total,
        'stable_count': stable,
        'unstable_count': unstable
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'error': str(e)}))
" 2>/dev/null || echo '{"has_fields": false}')
fi

# Write result JSON for verifier
cat > /tmp/stack_stability_analysis_result.json << EOF
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