#!/bin/bash
# Export script for sakila_temporal_gap_filling_reporting task

echo "=== Exporting Gap Filling Analysis Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
NOW=$(date +%s)

# --- Database Object Checks ---

# Check if views exist
CALENDAR_VIEW_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_july_2005_calendar'
" 2>/dev/null || echo "0")

ANALYSIS_VIEW_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_july_revenue_analysis'
" 2>/dev/null || echo "0")

# Check row count of the analysis view (Should be exactly 31 for July)
VIEW_ROW_COUNT=0
if [ "$ANALYSIS_VIEW_EXISTS" -gt 0 ]; then
    VIEW_ROW_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM v_july_revenue_analysis" 2>/dev/null || echo "0")
fi

# Check if Gap Dates are present in the view (The core requirement)
# We expect 2005-07-04 and 2005-07-15 to exist with 0 revenue
GAP_DATES_PRESENT=0
GAP_REVENUE_IS_ZERO=0

if [ "$ANALYSIS_VIEW_EXISTS" -gt 0 ]; then
    # Check existence
    GAP_DATES_PRESENT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*) FROM v_july_revenue_analysis 
        WHERE report_date IN ('2005-07-04', '2005-07-15');
    " 2>/dev/null || echo "0")
    
    # Check zero revenue (SUM of revenue for those days should be 0)
    GAP_REVENUE_CHECK=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COALESCE(SUM(daily_revenue), 0) FROM v_july_revenue_analysis 
        WHERE report_date IN ('2005-07-04', '2005-07-15');
    " 2>/dev/null || echo "-1")
    
    # Using python to check float equality to 0
    GAP_REVENUE_IS_ZERO=$(python3 -c "print(1 if abs($GAP_REVENUE_CHECK) < 0.01 else 0)" 2>/dev/null || echo "0")
fi

# Check Moving Average Column Existence
HAS_MOVING_AVG_COL=0
if [ "$ANALYSIS_VIEW_EXISTS" -gt 0 ]; then
    COLS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT COLUMN_NAME FROM COLUMNS 
        WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_july_revenue_analysis'
    " 2>/dev/null)
    if echo "$COLS" | grep -qi "avg"; then
        HAS_MOVING_AVG_COL=1
    fi
fi

# --- File Checks ---

MAIN_CSV="/home/ga/Documents/exports/july_revenue_continuous.csv"
ZERO_CSV="/home/ga/Documents/exports/zero_revenue_days.csv"

# Main CSV stats
MAIN_CSV_EXISTS="false"
MAIN_CSV_ROWS=0
MAIN_CSV_CREATED_DURING_TASK="false"
GAP_DATES_IN_CSV=0

if [ -f "$MAIN_CSV" ]; then
    MAIN_CSV_EXISTS="true"
    MTIME=$(stat -c%Y "$MAIN_CSV" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        MAIN_CSV_CREATED_DURING_TASK="true"
    fi
    # Subtract header
    TOTAL_LINES=$(wc -l < "$MAIN_CSV")
    MAIN_CSV_ROWS=$((TOTAL_LINES - 1))
    
    # Grep for the gap dates in the file
    if grep -q "2005-07-04" "$MAIN_CSV" && grep -q "2005-07-15" "$MAIN_CSV"; then
        GAP_DATES_IN_CSV=1
    fi
fi

# Zero CSV stats
ZERO_CSV_EXISTS="false"
ZERO_CSV_ROWS=0
ZERO_CSV_CREATED_DURING_TASK="false"
CORRECT_ZERO_DATES_FOUND=0

if [ -f "$ZERO_CSV" ]; then
    ZERO_CSV_EXISTS="true"
    MTIME=$(stat -c%Y "$ZERO_CSV" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        ZERO_CSV_CREATED_DURING_TASK="true"
    fi
    TOTAL_LINES=$(wc -l < "$ZERO_CSV")
    ZERO_CSV_ROWS=$((TOTAL_LINES - 1))
    
    # Check if specifically the gap dates are in there
    if grep -q "2005-07-04" "$ZERO_CSV" && grep -q "2005-07-15" "$ZERO_CSV"; then
        CORRECT_ZERO_DATES_FOUND=1
    fi
fi

# Create Result JSON
cat > /tmp/gap_analysis_result.json << EOF
{
    "calendar_view_exists": $CALENDAR_VIEW_EXISTS,
    "analysis_view_exists": $ANALYSIS_VIEW_EXISTS,
    "view_row_count": $VIEW_ROW_COUNT,
    "gap_dates_present_in_view": $GAP_DATES_PRESENT,
    "gap_revenue_is_zero": $GAP_REVENUE_IS_ZERO,
    "has_moving_avg_col": $HAS_MOVING_AVG_COL,
    "main_csv_exists": $MAIN_CSV_EXISTS,
    "main_csv_rows": $MAIN_CSV_ROWS,
    "main_csv_created_during_task": $MAIN_CSV_CREATED_DURING_TASK,
    "gap_dates_in_csv": $GAP_DATES_IN_CSV,
    "zero_csv_exists": $ZERO_CSV_EXISTS,
    "zero_csv_correct_content": $CORRECT_ZERO_DATES_FOUND,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON generated."
cat /tmp/gap_analysis_result.json
echo "=== Export Complete ==="