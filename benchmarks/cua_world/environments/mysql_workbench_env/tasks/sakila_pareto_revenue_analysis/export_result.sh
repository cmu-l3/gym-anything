#!/bin/bash
# Export script for sakila_pareto_revenue_analysis task

echo "=== Exporting Sakila Pareto Analysis Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Verify Views Exist
LTV_VIEW_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_customer_ltv'
" 2>/dev/null)
LTV_VIEW_EXISTS=${LTV_VIEW_EXISTS:-0}

PARETO_VIEW_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_pareto_revenue'
" 2>/dev/null)
PARETO_VIEW_EXISTS=${PARETO_VIEW_EXISTS:-0}

# 2. Verify View Logic (Programmatic check of the view's output)
# We check if the view actually runs and produces expected columns
VIEW_COLUMNS_OK="false"
RUNNING_TOTAL_LOGIC_OK="false"
PCT_CALC_OK="false"
TOTAL_REVENUE_SUM=0

if [ "$PARETO_VIEW_EXISTS" -gt 0 ]; then
    # Check columns
    COLS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT COLUMN_NAME FROM COLUMNS
        WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_pareto_revenue'
    " 2>/dev/null)
    
    HAS_RUNNING=$(echo "$COLS" | grep -qi "running" && echo "true" || echo "false")
    HAS_PCT=$(echo "$COLS" | grep -qi "pct\|percent" && echo "true" || echo "false")
    
    if [ "$HAS_RUNNING" = "true" ] && [ "$HAS_PCT" = "true" ]; then
        VIEW_COLUMNS_OK="true"
    fi

    # Check data logic (Get top row and bottom row)
    # Expected: Top row has small pct, Bottom row has 100% (or near it)
    DATA_CHECK=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT 
            MIN(cumulative_pct), 
            MAX(cumulative_pct),
            COUNT(*),
            MAX(running_total)
        FROM v_pareto_revenue
    " 2>/dev/null)
    
    MIN_PCT=$(echo "$DATA_CHECK" | awk '{print $1}')
    MAX_PCT=$(echo "$DATA_CHECK" | awk '{print $2}')
    ROW_COUNT=$(echo "$DATA_CHECK" | awk '{print $3}')
    MAX_RUNNING=$(echo "$DATA_CHECK" | awk '{print $4}')

    # Verify logic: Max pct should be close to 100
    # Use python for float comparison
    PCT_CALC_OK=$(python3 -c "print('true' if $MAX_PCT >= 99.0 and $MAX_PCT <= 100.1 else 'false')" 2>/dev/null || echo "false")
    
    # Verify logic: Running total should increase
    # We'll assume if max_running > 0 and row count > 500, it's likely working
    RUNNING_TOTAL_LOGIC_OK=$(python3 -c "print('true' if float('$MAX_RUNNING') > 10000 and int('$ROW_COUNT') > 500 else 'false')" 2>/dev/null || echo "false")
fi

# 3. Verify CSV Export
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0
CSV_MAX_PCT=0
OUTPUT_FILE="/home/ga/Documents/exports/vip_whales.csv"

if [ -f "$OUTPUT_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Count rows (minus header)
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0

    # Check content (read the last line's percentage to verify cutoff)
    # Find which column is percentage (look for header)
    HEADER=$(head -1 "$OUTPUT_FILE")
    # Assuming standard export, try to find numeric values in last line
    LAST_LINE=$(tail -1 "$OUTPUT_FILE")
    
    # Heuristic: The percentage should be the last or near last column and <= 80 (allow small float tolerance)
    # We will pass the raw last line to python for robust checking
    CSV_VALID_CUTOFF=$(python3 -c "
import sys
try:
    line = '$LAST_LINE'.replace('\"', '').split(',')
    # Find any float <= 81.0 in the row
    valid = any(0.0 < float(x) <= 81.0 for x in line if x.replace('.', '', 1).isdigit())
    print('true' if valid else 'false')
except:
    print('false')
" 2>/dev/null)
else
    CSV_VALID_CUTOFF="false"
fi

cat > /tmp/pareto_result.json << EOF
{
    "ltv_view_exists": $LTV_VIEW_EXISTS,
    "pareto_view_exists": $PARETO_VIEW_EXISTS,
    "view_columns_ok": $VIEW_COLUMNS_OK,
    "pct_calc_logic_ok": $PCT_CALC_OK,
    "running_total_logic_ok": $RUNNING_TOTAL_LOGIC_OK,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "csv_valid_cutoff": $CSV_VALID_CUTOFF,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result generated at /tmp/pareto_result.json"
echo "=== Export Complete ==="