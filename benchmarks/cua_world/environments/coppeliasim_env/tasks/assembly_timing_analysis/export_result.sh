#!/bin/bash
echo "=== Exporting assembly_timing_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/assembly_timing_analysis_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/cycle_timing.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/timing_report.json"

take_screenshot /tmp/assembly_timing_analysis_end_screenshot.png

CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"has_timing": false, "cycles_with_positive_duration": 0, "avg_duration": 0.0, "max_duration": 0.0}'

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
    with open('/home/ga/Documents/CoppeliaSim/exports/cycle_timing.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_timing": False, "cycles_with_positive_duration": 0, "avg_duration": 0.0, "max_duration": 0.0}))
        sys.exit(0)
    headers = list(rows[0].keys())
    dur_col = find_col(headers, ['cycle_duration_s','duration_s','duration','cycle_time_s','time_s'])
    has_timing = dur_col is not None
    if has_timing:
        durations = []
        for r in rows:
            try:
                d = float(r[dur_col])
                if d > 0:
                    durations.append(d)
            except:
                pass
        avg_d = sum(durations)/len(durations) if durations else 0.0
        max_d = max(durations) if durations else 0.0
        positive = len(durations)
    else:
        positive = 0
        avg_d = 0.0
        max_d = 0.0
    print(json.dumps({"has_timing": has_timing, "cycles_with_positive_duration": positive,
                      "avg_duration": avg_d, "max_duration": max_d}))
except Exception as e:
    print(json.dumps({"has_timing": False, "cycles_with_positive_duration": 0, "avg_duration": 0.0, "max_duration": 0.0, "error": str(e)}))
PYEOF
    )
fi

JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_cycles": 0, "avg_cycle_time_s": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
    JSON_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_cycles','avg_cycle_time_s']
    has_fields = all(k in d for k in req)
    print(json.dumps({'has_fields': has_fields, 'total_cycles': int(d.get('total_cycles',0)), 'avg_cycle_time_s': float(d.get('avg_cycle_time_s',0))}))
except Exception as e:
    print(json.dumps({'has_fields': False, 'total_cycles': 0, 'avg_cycle_time_s': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "total_cycles": 0, "avg_cycle_time_s": 0.0}')
fi

cat > /tmp/assembly_timing_analysis_result.json << EOF
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
