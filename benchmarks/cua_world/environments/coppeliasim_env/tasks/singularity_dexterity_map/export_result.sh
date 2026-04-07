#!/bin/bash
echo "=== Exporting singularity_dexterity_map Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/singularity_dexterity_map_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/dexterity_samples.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/dexterity_report.json"

take_screenshot /tmp/singularity_dexterity_map_end_screenshot.png

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_required_cols": false, "manipulability_variance": 0.0, "valid_manip_count": 0, "joints_spanning_30deg": 0}'

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

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/dexterity_samples.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_required_cols": False, "manipulability_variance": 0.0, "valid_manip_count": 0, "joints_spanning_30deg": 0}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    manip_col = find_col(headers, ['manipulability', 'manip', 'manip_index'])
    cond_col = find_col(headers, ['condition_number', 'cond', 'cond_num'])
    
    # Joint columns
    j_cols = []
    for j in range(6):
        col = find_col(headers, [f'j{j}_deg', f'j{j}', f'joint{j}', f'q{j}'])
        j_cols.append(col)
        
    has_required_cols = manip_col is not None and cond_col is not None
    
    manip_variance = 0.0
    valid_manip_count = 0
    joints_spanning_30deg = 0
    
    if has_required_cols:
        manips = []
        for r in rows:
            try:
                m = float(r[manip_col])
                if m >= 0:
                    manips.append(m)
            except:
                pass
        valid_manip_count = len(manips)
        if valid_manip_count > 0:
            manip_variance = max(manips) - min(manips)
            
    # Calculate joint ranges
    for jc in j_cols:
        if jc:
            try:
                vals = [float(r[jc]) for r in rows if r.get(jc, '').strip()]
                if vals:
                    j_range = max(vals) - min(vals)
                    if j_range >= 30.0:
                        joints_spanning_30deg += 1
            except:
                pass

    print(json.dumps({
        "has_required_cols": has_required_cols,
        "manipulability_variance": manip_variance,
        "valid_manip_count": valid_manip_count,
        "joints_spanning_30deg": joints_spanning_30deg
    }))
except Exception as e:
    print(json.dumps({"has_required_cols": False, "manipulability_variance": 0.0, "valid_manip_count": 0, "joints_spanning_30deg": 0, "error": str(e)}))
PYEOF
    )
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_samples": 0, "worst_config_valid": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_samples', 'singular_count', 'singular_threshold', 'max_manipulability', 'min_manipulability', 'mean_manipulability', 'worst_config_deg']
    has_fields = all(k in d for k in req)
    
    worst_config = d.get('worst_config_deg', [])
    worst_config_valid = isinstance(worst_config, list) and len(worst_config) >= 6
    
    print(json.dumps({
        'has_fields': has_fields, 
        'total_samples': int(d.get('total_samples', 0)), 
        'worst_config_valid': worst_config_valid
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_samples': 0, 'worst_config_valid': False}))
" 2>/dev/null || echo '{"has_fields": false, "total_samples": 0, "worst_config_valid": false}')
fi

cat > /tmp/singularity_dexterity_map_result.json << EOF
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