#!/bin/bash
echo "=== Exporting force_contact_probing Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/force_contact_probing_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/contact_probing.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/probing_report.json"

# Take final screenshot
take_screenshot /tmp/force_contact_probing_end_screenshot.png

# Check CSV file
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_force_cols": false, "force_data_rows": 0, "spatial_span_x": 0.0, "spatial_span_y": 0.0, "unique_targets": 0, "contacts_detected": 0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    # Count data rows (exclude header)
    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    print(len(rows))
except:
    print(0)
" 2>/dev/null || echo "0")

    # Analyze CSV headers and content
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/contact_probing.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_force_cols": False, "force_data_rows": 0, "spatial_span_x": 0.0, "spatial_span_y": 0.0, "unique_targets": 0, "contacts_detected": 0}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    
    # Locate required columns
    fx = find_col(headers, ['force_x', 'fx'])
    fy = find_col(headers, ['force_y', 'fy'])
    fz = find_col(headers, ['force_z', 'fz'])
    tx = find_col(headers, ['torque_x', 'tx'])
    ty = find_col(headers, ['torque_y', 'ty'])
    tz = find_col(headers, ['torque_z', 'tz'])
    cz = find_col(headers, ['contact_z', 'cz', 'z'])
    targ_x = find_col(headers, ['target_x', 'probe_x', 'x'])
    targ_y = find_col(headers, ['target_y', 'probe_y', 'y'])
    cd = find_col(headers, ['contact_detected', 'contact', 'detected'])

    has_force_cols = all(c is not None for c in [fx, fy, fz, tx, ty, tz, cz])
    
    force_data_rows = 0
    if has_force_cols:
        for r in rows:
            try:
                # check if force_z is numeric
                float(r[fz])
                force_data_rows += 1
            except:
                pass

    xs = []
    ys = []
    if targ_x and targ_y:
        for r in rows:
            try:
                xs.append(float(r[targ_x]))
                ys.append(float(r[targ_y]))
            except:
                pass

    span_x = max(xs) - min(xs) if xs else 0.0
    span_y = max(ys) - min(ys) if ys else 0.0
    unique_targets = len(set((round(x, 3), round(y, 3)) for x, y in zip(xs, ys))) if xs else 0

    contacts_detected = 0
    if cd:
        for r in rows:
            val = str(r[cd]).strip().lower()
            if val in ['true', '1', 'yes', 't', 'detected']:
                contacts_detected += 1
    elif has_force_cols: # fallback if boolean col missing but force exists
        for r in rows:
            try:
                if abs(float(r[fz])) > 0.001:
                    contacts_detected += 1
            except:
                pass

    print(json.dumps({
        "has_force_cols": has_force_cols,
        "force_data_rows": force_data_rows,
        "spatial_span_x": span_x,
        "spatial_span_y": span_y,
        "unique_targets": unique_targets,
        "contacts_detected": contacts_detected
    }))
except Exception as e:
    print(json.dumps({"has_force_cols": False, "force_data_rows": 0, "spatial_span_x": 0.0, "spatial_span_y": 0.0, "unique_targets": 0, "contacts_detected": 0, "error": str(e)}))
PYEOF
    )
fi

# Check JSON report file
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_probes": 0, "contacts_detected": 0, "avg_contact_force_n": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_probes', 'contacts_detected', 'avg_contact_force_n', 'max_force_n', 'surface_height_range_m', 'grid_rows', 'grid_cols']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'total_probes': int(d.get('total_probes', 0)),
        'contacts_detected': int(d.get('contacts_detected', 0)),
        'avg_contact_force_n': float(d.get('avg_contact_force_n', 0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_probes': 0, 'contacts_detected': 0, 'avg_contact_force_n': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "total_probes": 0, "contacts_detected": 0, "avg_contact_force_n": 0.0}')
fi

# Write aggregated result JSON
cat > /tmp/force_contact_probing_result.json << EOF
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