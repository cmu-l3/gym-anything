#!/bin/bash
# Export script for sakila_window_analytics_reporting

echo "=== Exporting Sakila Analytics Result ==="

# Record end time and retrieve start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Database Verification Helper Functions
MYSQL_CMD="mysql -u root -pGymAnything#2024 sakila -N -e"

# Check View 1: v_film_revenue_ranked
echo "Checking v_film_revenue_ranked..."
VIEW1_EXISTS=$($MYSQL_CMD "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_film_revenue_ranked'" 2>/dev/null || echo "0")
VIEW1_COLS=$($MYSQL_CMD "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_film_revenue_ranked' AND COLUMN_NAME IN ('category_name', 'film_title', 'total_revenue', 'revenue_rank')" 2>/dev/null || echo "0")
# Check if rank function was likely used by checking if we have Rank 1s for multiple categories
VIEW1_RANKS_VALID=$($MYSQL_CMD "SELECT COUNT(DISTINCT category_name) FROM v_film_revenue_ranked WHERE revenue_rank = 1" 2>/dev/null || echo "0")
VIEW1_ROWS=$($MYSQL_CMD "SELECT COUNT(*) FROM v_film_revenue_ranked" 2>/dev/null || echo "0")

# Check View 2: v_customer_rfm
echo "Checking v_customer_rfm..."
VIEW2_EXISTS=$($MYSQL_CMD "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_customer_rfm'" 2>/dev/null || echo "0")
# Check for specific score columns
VIEW2_COLS=$($MYSQL_CMD "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_customer_rfm' AND COLUMN_NAME IN ('recency_score', 'frequency_score', 'monetary_score')" 2>/dev/null || echo "0")
# Verify score range is 1-4 (NTILE 4)
VIEW2_SCORE_RANGE_VALID=$($MYSQL_CMD "SELECT COUNT(*) FROM v_customer_rfm WHERE recency_score NOT BETWEEN 1 AND 4 OR frequency_score NOT BETWEEN 1 AND 4 OR monetary_score NOT BETWEEN 1 AND 4" 2>/dev/null || echo "999")
VIEW2_ROWS=$($MYSQL_CMD "SELECT COUNT(*) FROM v_customer_rfm" 2>/dev/null || echo "0")

# Check Table: rpt_monthly_category_performance
echo "Checking rpt_monthly_category_performance..."
TABLE_EXISTS=$($MYSQL_CMD "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='rpt_monthly_category_performance'" 2>/dev/null || echo "0")
TABLE_ROWS=$($MYSQL_CMD "SELECT COUNT(*) FROM rpt_monthly_category_performance" 2>/dev/null || echo "0")
# Check logic: percentage should sum to roughly 100 per month
PCT_LOGIC_VALID=$($MYSQL_CMD "SELECT COUNT(*) FROM (SELECT report_month, SUM(revenue_pct_of_month) as s FROM rpt_monthly_category_performance GROUP BY report_month HAVING s < 98 OR s > 102) as bad_months" 2>/dev/null || echo "999")

# Check Procedure: sp_refresh_category_performance
echo "Checking procedure..."
PROC_EXISTS=$($MYSQL_CMD "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_NAME='sp_refresh_category_performance'" 2>/dev/null || echo "0")

# 3. File Verification
CSV1_PATH="/home/ga/Documents/exports/film_revenue_ranked.csv"
CSV2_PATH="/home/ga/Documents/exports/monthly_category_performance.csv"

check_file() {
    local path=$1
    if [ -f "$path" ]; then
        local mtime=$(stat -c%Y "$path" 2>/dev/null || echo "0")
        local size=$(stat -c%s "$path" 2>/dev/null || echo "0")
        local lines=$(wc -l < "$path" 2>/dev/null || echo "0")
        local new="false"
        if [ "$mtime" -gt "$TASK_START" ]; then new="true"; fi
        echo "{\"exists\": true, \"new\": $new, \"size\": $size, \"lines\": $lines}"
    else
        echo "{\"exists\": false, \"new\": false, \"size\": 0, \"lines\": 0}"
    fi
}

CSV1_INFO=$(check_file "$CSV1_PATH")
CSV2_INFO=$(check_file "$CSV2_PATH")

# 4. Construct Result JSON
# Use a temp file to avoid permission issues, then copy
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "view_film_revenue": {
        "exists": $([ "$VIEW1_EXISTS" -gt 0 ] && echo "true" || echo "false"),
        "cols_match_count": $VIEW1_COLS,
        "valid_ranks_count": $VIEW1_RANKS_VALID,
        "row_count": $VIEW1_ROWS
    },
    "view_customer_rfm": {
        "exists": $([ "$VIEW2_EXISTS" -gt 0 ] && echo "true" || echo "false"),
        "cols_match_count": $VIEW2_COLS,
        "invalid_scores_count": $VIEW2_SCORE_RANGE_VALID,
        "row_count": $VIEW2_ROWS
    },
    "table_rpt": {
        "exists": $([ "$TABLE_EXISTS" -gt 0 ] && echo "true" || echo "false"),
        "row_count": $TABLE_ROWS,
        "bad_pct_months_count": $PCT_LOGIC_VALID
    },
    "proc_refresh": {
        "exists": $([ "$PROC_EXISTS" -gt 0 ] && echo "true" || echo "false")
    },
    "csv_film_revenue": $CSV1_INFO,
    "csv_monthly_perf": $CSV2_INFO,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with lenient permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json