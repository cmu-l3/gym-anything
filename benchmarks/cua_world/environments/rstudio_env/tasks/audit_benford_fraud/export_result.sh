#!/bin/bash
echo "=== Exporting audit_benford_fraud result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

PLOT_PATH="/home/ga/RProjects/output/benford_plot.png"
STATS_PATH="/home/ga/RProjects/output/benford_stats.csv"
SUSPECTS_PATH="/home/ga/RProjects/output/suspect_invoices.csv"
SCRIPT_PATH="/home/ga/RProjects/audit_analysis.R"

# Initialize variables
PLOT_EXISTS=false
PLOT_IS_NEW=false
PLOT_SIZE_KB=0

STATS_EXISTS=false
STATS_IS_NEW=false
STATS_ROW_COUNT=0
STATS_HAS_COLUMNS=false
STATS_HAS_DIGIT_50=false

SUSPECTS_EXISTS=false
SUSPECTS_IS_NEW=false
SUSPECTS_ROW_COUNT=0
SUSPECTS_HAS_COLUMNS=false

SCRIPT_EXISTS=false
SCRIPT_IS_NEW=false
SCRIPT_USES_BENFORD=false

# 1. Check Plot
if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS=true
    PLOT_MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    [ "$PLOT_MTIME" -gt "$TASK_START" ] && PLOT_IS_NEW=true
    PLOT_SIZE_KB=$(du -k "$PLOT_PATH" 2>/dev/null | cut -f1)
fi

# 2. Check Stats CSV
if [ -f "$STATS_PATH" ]; then
    STATS_EXISTS=true
    STATS_MTIME=$(stat -c %Y "$STATS_PATH" 2>/dev/null || echo "0")
    [ "$STATS_MTIME" -gt "$TASK_START" ] && STATS_IS_NEW=true
    STATS_ROW_COUNT=$(awk 'NR>1' "$STATS_PATH" | wc -l)
    
    # Python validation for Stats CSV
    PY_STATS_OUT=$(python3 << PYEOF
import csv
import sys
try:
    with open("$STATS_PATH", "r") as f:
        reader = csv.DictReader(f)
        headers = [h.lower() for h in (reader.fieldnames or [])]
        
        has_cols = any('digit' in h for h in headers) and (any('z.score' in h for h in headers) or any('z' == h for h in headers) or any('difference' in h for h in headers))
        
        has_50 = False
        for row in reader:
            for k, v in row.items():
                if 'digit' in k.lower() and str(v).strip() == '50':
                    has_50 = True
                    break
                    
        print(f"{str(has_cols).lower()},{str(has_50).lower()}")
except Exception as e:
    print("false,false")
PYEOF
)
    STATS_HAS_COLUMNS=$(echo "$PY_STATS_OUT" | cut -d',' -f1)
    STATS_HAS_DIGIT_50=$(echo "$PY_STATS_OUT" | cut -d',' -f2)
fi

# 3. Check Suspects CSV
if [ -f "$SUSPECTS_PATH" ]; then
    SUSPECTS_EXISTS=true
    SUSPECTS_MTIME=$(stat -c %Y "$SUSPECTS_PATH" 2>/dev/null || echo "0")
    [ "$SUSPECTS_MTIME" -gt "$TASK_START" ] && SUSPECTS_IS_NEW=true
    SUSPECTS_ROW_COUNT=$(awk 'NR>1' "$SUSPECTS_PATH" | wc -l)
    
    # Python validation for Suspects CSV
    PY_SUSPECTS_OUT=$(python3 << PYEOF
import csv
try:
    with open("$SUSPECTS_PATH", "r") as f:
        reader = csv.DictReader(f)
        headers = [h.lower() for h in (reader.fieldnames or [])]
        
        # Check if original columns like Amount, VendorNum, or Date exist
        has_cols = any('amount' in h for h in headers) and any('vendor' in h or 'inv' in h or 'date' in h for h in headers)
        print(str(has_cols).lower())
except Exception as e:
    print("false")
PYEOF
)
    SUSPECTS_HAS_COLUMNS=$PY_SUSPECTS_OUT
fi

# 4. Check Script
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS=true
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    [ "$SCRIPT_MTIME" -gt "$TASK_START" ] && SCRIPT_IS_NEW=true
    
    CODE=$(grep -v '^\s*#' "$SCRIPT_PATH")
    if echo "$CODE" | grep -qiE "benford\s*\(|benford\.analysis"; then
        SCRIPT_USES_BENFORD=true
    fi
fi

# Build result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_kb": $PLOT_SIZE_KB,
    "stats_exists": $STATS_EXISTS,
    "stats_is_new": $STATS_IS_NEW,
    "stats_row_count": $STATS_ROW_COUNT,
    "stats_has_columns": $STATS_HAS_COLUMNS,
    "stats_has_digit_50": $STATS_HAS_DIGIT_50,
    "suspects_exists": $SUSPECTS_EXISTS,
    "suspects_is_new": $SUSPECTS_IS_NEW,
    "suspects_row_count": $SUSPECTS_ROW_COUNT,
    "suspects_has_columns": $SUSPECTS_HAS_COLUMNS,
    "script_exists": $SCRIPT_EXISTS,
    "script_is_new": $SCRIPT_IS_NEW,
    "script_uses_benford": $SCRIPT_USES_BENFORD
}
EOF

# Move to final location safely
rm -f /tmp/audit_benford_fraud_result.json 2>/dev/null || sudo rm -f /tmp/audit_benford_fraud_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/audit_benford_fraud_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/audit_benford_fraud_result.json
chmod 666 /tmp/audit_benford_fraud_result.json 2>/dev/null || sudo chmod 666 /tmp/audit_benford_fraud_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/audit_benford_fraud_result.json