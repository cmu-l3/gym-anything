#!/bin/bash
echo "=== Exporting palletizing_pattern_planning Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/palletizing_task_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/pallet_positions.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/pallet_report.json"

# Take final screenshot
take_screenshot /tmp/palletizing_task_end_screenshot.png

# Default values
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_required_cols": false, "span_x": 0.0, "span_y": 0.0, "valid_deviations": 0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        print(len(list(csv.DictReader(f))))
except:
    print(0)
" 2>/dev/null || echo "0")

    # Analyze CSV for grid spatial properties and required columns
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/pallet_positions.csv') as f:
        rows = list(csv.DictReader(f))
    
    if not rows:
        print(json.dumps({"has_required_cols": False, "span_x": 0.0, "span_y": 0.0, "valid_deviations": 0}))
        sys.exit(0)

    headers = [h.strip().lower() for h in rows[0].keys()]
    
    # Check for target_x, target_y, deviation_mm (allow some flexibility in names)
    tx_col = next((h for h in rows[0].keys() if 'target_x' in h.lower()), None)
    ty_col = next((h for h in rows[0].keys() if 'target_y' in h.lower()), None)
    dev_col = next((h for h in rows[0].keys() if 'dev' in h.lower()), None)
    
    has_required_cols = tx_col is not None and ty_col is not None and dev_col is not None
    span_x = span_y = 0.0
    valid_devs = 0

    if tx_col and ty_col:
        tx_vals = [float(r[tx_col]) for r in rows if r.get(tx_col, '').strip()]
        ty_vals = [float(r[ty_col]) for r in rows if r.get(ty_col, '').strip()]
        if tx_vals: span_x = max(tx_vals) - min(tx_vals)
        if ty_vals: span_y = max(ty_vals) - min(ty_vals)

    if dev_col:
        for r in rows:
            try:
                if float(r[dev_col]) >= 0:
                    valid_devs += 1
            except:
                pass

    print(json.dumps({
        "has_required_cols": has_required_cols,
        "span_x": span_x,
        "span_y": span_y,
        "valid_deviations": valid_devs
    }))
except Exception as e:
    print(json.dumps({"has_required_cols": False, "span_x": 0.0, "span_y": 0.0, "valid_deviations": 0, "error": str(e)}))
PYEOF
    )
fi

# Check JSON
JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_FIELDS='{"has_fields": false, "total_positions": 0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi

    JSON_FIELDS=$(python3 << 'PYEOF'
import json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/pallet_report.json') as f:
        d = json.load(f)
    req = ['grid_rows', 'grid_cols', 'total_positions', 'cell_spacing_x_m', 'cell_spacing_y_m', 'mean_deviation_mm', 'max_deviation_mm']
    has_fields = all(k in d for k in req)
    tot = int(d.get('total_positions', 0))
    print(json.dumps({'has_fields': has_fields, 'total_positions': tot}))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_positions': 0}))
PYEOF
    )
fi

# Create result JSON
cat > /tmp/palletizing_task_result.json << EOF
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