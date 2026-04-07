#!/bin/bash
echo "=== Exporting conveyor_line_tracking_study Result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/conveyor_task_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/tracking_data.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/tracking_report.json"
TTT="/home/ga/Documents/CoppeliaSim/exports/line_tracking_final.ttt"

# 1. Parse CSV using Python
CSV_ANALYSIS=$(python3 -c "
import csv, json, sys

def get_col(headers, candidates):
    for c in candidates:
        if c in headers:
            return c
    return None

try:
    with open('$CSV') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    if not rows:
        print(json.dumps({'exists': True, 'rows': 0}))
        sys.exit(0)
        
    headers = [h.strip().lower() for h in rows[0].keys()]
    
    ix_col = get_col(headers, ['item_x', 'conveyor_x', 'dummy_x', 'x'])
    tx_col = get_col(headers, ['tip_x', 'robot_x', 'actual_x'])
    err_col = get_col(headers, ['error_m', 'error', 'tracking_error'])
    
    ixs = []
    if ix_col:
        ix_real = list(rows[0].keys())[headers.index(ix_col)]
        ixs = [float(r[ix_real]) for r in rows if r[ix_real].strip()]
        
    txs = []
    if tx_col:
        tx_real = list(rows[0].keys())[headers.index(tx_col)]
        txs = [float(r[tx_real]) for r in rows if r[tx_real].strip()]
        
    ix_increasing = all(ixs[i] <= ixs[i+1] for i in range(len(ixs)-1)) if len(ixs) > 1 else False
    ix_span = max(ixs) - min(ixs) if ixs else 0.0
    tx_span = max(txs) - min(txs) if txs else 0.0
    
    print(json.dumps({
        'exists': True,
        'rows': len(rows),
        'has_item_x': ix_col is not None,
        'has_tip_x': tx_col is not None,
        'has_error': err_col is not None,
        'ix_increasing': ix_increasing,
        'ix_span': ix_span,
        'tx_span': tx_span
    }))
except Exception as e:
    print(json.dumps({'exists': False, 'rows': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"exists": false, "rows": 0}')

# 2. Parse JSON
JSON_ANALYSIS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['total_steps', 'simulated_duration_s', 'mean_error_m', 'min_error_m', 'max_error_m', 'final_item_x']
    has_fields = all(k in d for k in req)
    total_steps = int(d.get('total_steps', 0))
    print(json.dumps({'exists': True, 'has_fields': has_fields, 'total_steps': total_steps}))
except Exception as e:
    print(json.dumps({'exists': False, 'has_fields': False, 'total_steps': 0}))
" 2>/dev/null || echo '{"exists": false, "has_fields": false, "total_steps": 0}')

# 3. Check TTT and anti-gaming
TTT_EXISTS="false"
TTT_HAS_DUMMY="false"
if [ -f "$TTT" ]; then
    TTT_EXISTS="true"
    # Simple binary grep to verify the dummy object was actually created in the saved scene
    if grep -qa "conveyor_item" "$TTT"; then
        TTT_HAS_DUMMY="true"
    fi
fi

# Check timestamps to ensure files were generated during the task
CSV_NEW="false"
JSON_NEW="false"
TTT_NEW="false"
[ -f "$CSV" ] && [ "$(stat -c %Y "$CSV")" -gt "$TASK_START" ] && CSV_NEW="true"
[ -f "$JSON" ] && [ "$(stat -c %Y "$JSON")" -gt "$TASK_START" ] && JSON_NEW="true"
[ -f "$TTT" ] && [ "$(stat -c %Y "$TTT")" -gt "$TASK_START" ] && TTT_NEW="true"

# Save consolidated results for the verifier
TEMP_JSON=$(mktemp /tmp/conveyor_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_new": $CSV_NEW,
    "json_new": $JSON_NEW,
    "ttt_new": $TTT_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_analysis": $JSON_ANALYSIS,
    "ttt_exists": $TTT_EXISTS,
    "ttt_has_dummy": $TTT_HAS_DUMMY
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="