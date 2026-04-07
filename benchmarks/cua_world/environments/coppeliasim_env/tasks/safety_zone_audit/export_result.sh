#!/bin/bash
echo "=== Exporting safety_zone_audit Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/safety_zone_audit_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/safety_zone_log.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/safety_compliance_report.json"

# Take final screenshot
take_screenshot /tmp/safety_zone_audit_end_screenshot.png

# Check CSV properties and run content analysis
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        reader = csv.DictReader(f)
        print(len(list(reader)))
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
    with open('/home/ga/Documents/CoppeliaSim/exports/safety_zone_log.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
    if not rows:
        print(json.dumps({"valid_rows": 0, "num_profiles": 0, "violations_count": 0, "geo_correct_count": 0, "x_range": 0, "y_range": 0, "z_range": 0}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    x_col = find_col(headers, ['ee_x', 'x', 'measured_x', 'actual_x'])
    y_col = find_col(headers, ['ee_y', 'y', 'measured_y', 'actual_y'])
    z_col = find_col(headers, ['ee_z', 'z', 'measured_z', 'actual_z'])
    v_col = find_col(headers, ['in_violation', 'violation', 'is_violation'])
    p_col = find_col(headers, ['profile_id', 'profile', 'motion_id'])

    if not (x_col and y_col and z_col and v_col and p_col):
        print(json.dumps({"valid_rows": 0, "num_profiles": 0, "violations_count": 0, "geo_correct_count": 0, "x_range": 0, "y_range": 0, "z_range": 0}))
        sys.exit(0)

    profiles = set()
    violations = 0
    geo_correct = 0
    valid_rows = 0
    xs, ys, zs = [], [], []

    for r in rows:
        try:
            x, y, z = float(r[x_col]), float(r[y_col]), float(r[z_col])
            v_val = str(r[v_col]).strip().lower()
            v = 1 if v_val in ['1', 'true', 'yes'] else 0
            pid = str(r[p_col]).strip()
            
            profiles.add(pid)
            if v == 1:
                violations += 1
            
            # Verify geometric checks matches the stated cuboid bounds
            in_zone = (0.2 <= x <= 0.6) and (-0.4 <= y <= 0.0) and (0.0 <= z <= 0.4)
            expected_v = 1 if in_zone else 0
            if v == expected_v:
                geo_correct += 1
            
            xs.append(x)
            ys.append(y)
            zs.append(z)
            valid_rows += 1
        except Exception:
            pass

    x_range = max(xs) - min(xs) if xs else 0.0
    y_range = max(ys) - min(ys) if ys else 0.0
    z_range = max(zs) - min(zs) if zs else 0.0

    print(json.dumps({
        "valid_rows": valid_rows,
        "num_profiles": len(profiles),
        "violations_count": violations,
        "geo_correct_count": geo_correct,
        "x_range": x_range,
        "y_range": y_range,
        "z_range": z_range
    }))
except Exception as e:
    print(json.dumps({"valid_rows": 0, "num_profiles": 0, "violations_count": 0, "geo_correct_count": 0, "x_range": 0, "y_range": 0, "z_range": 0, "error": str(e)}))
PYEOF
    )
else:
    CSV_ANALYSIS='{"valid_rows": 0, "num_profiles": 0, "violations_count": 0, "geo_correct_count": 0, "x_range": 0, "y_range": 0, "z_range": 0}'
fi

# Check JSON properties and format
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_steps_monitored": 0, "total_violations": 0, "compliant": null}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_steps_monitored', 'total_violations', 'violation_rate_pct', 'num_profiles', 'profiles_with_violations', 'max_penetration_m', 'zone_min', 'zone_max', 'compliant']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'total_steps_monitored': int(d.get('total_steps_monitored', 0)),
        'total_violations': int(d.get('total_violations', 0)),
        'compliant': d.get('compliant', None)
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_steps_monitored': 0, 'total_violations': 0, 'compliant': None}))
" 2>/dev/null || echo '{"has_fields": false, "total_steps_monitored": 0, "total_violations": 0, "compliant": null}')
fi

# Consolidate results for verifier logic
cat > /tmp/safety_zone_audit_result.json << EOF
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