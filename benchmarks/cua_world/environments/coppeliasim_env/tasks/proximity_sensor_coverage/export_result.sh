#!/bin/bash
echo "=== Exporting proximity_sensor_coverage Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/proximity_sensor_coverage_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/sensor_coverage.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/sensor_analysis.json"

take_screenshot /tmp/proximity_sensor_coverage_end_screenshot.png

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_coverage_col": false, "placements_with_valid_pct": 0, "max_coverage_pct": 0.0, "mean_coverage_pct": 0.0}'

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
    with open('/home/ga/Documents/CoppeliaSim/exports/sensor_coverage.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_coverage_col": False, "placements_with_valid_pct": 0, "max_coverage_pct": 0.0, "mean_coverage_pct": 0.0}))
        sys.exit(0)
    headers = list(rows[0].keys())
    pct_col = find_col(headers, ['coverage_pct','coverage','pct','detection_pct'])
    has_coverage_col = pct_col is not None
    if has_coverage_col:
        pcts = []
        for r in rows:
            try:
                v = float(r[pct_col])
                if 0.0 <= v <= 100.0:
                    pcts.append(v)
            except:
                pass
        valid_count = len(pcts)
        max_pct = max(pcts) if pcts else 0.0
        mean_pct = sum(pcts)/len(pcts) if pcts else 0.0
    else:
        valid_count = 0
        max_pct = 0.0
        mean_pct = 0.0
    print(json.dumps({"has_coverage_col": has_coverage_col, "placements_with_valid_pct": valid_count,
                      "max_coverage_pct": max_pct, "mean_coverage_pct": mean_pct}))
except Exception as e:
    print(json.dumps({"has_coverage_col": False, "placements_with_valid_pct": 0, "max_coverage_pct": 0.0, "mean_coverage_pct": 0.0, "error": str(e)}))
PYEOF
    )
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_placements": 0, "best_coverage_pct": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_placements','best_placement_id','best_coverage_pct','recommended_x','recommended_y','recommended_z']
    has_fields = all(k in d for k in req)
    print(json.dumps({'has_fields': has_fields, 'total_placements': int(d.get('total_placements',0)), 'best_coverage_pct': float(d.get('best_coverage_pct',0))}))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_placements': 0, 'best_coverage_pct': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "total_placements": 0, "best_coverage_pct": 0.0}')
fi

cat > /tmp/proximity_sensor_coverage_result.json << EOF
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
