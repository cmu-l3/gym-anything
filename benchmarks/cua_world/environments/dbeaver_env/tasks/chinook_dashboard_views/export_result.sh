#!/bin/bash
# Export script for chinook_dashboard_views
# Inspects database state and output files

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Documents/databases/chinook.db"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo 0)

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Inspect Files
check_file_info() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local fsize=$(stat -c%s "$fpath" 2>/dev/null || echo 0)
        local fmtime=$(stat -c%Y "$fpath" 2>/dev/null || echo 0)
        local created_during_task="false"
        if [ "$fmtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "{\"exists\": true, \"size\": $fsize, \"created_during_task\": $created_during_task}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

FILE_SCRIPT=$(check_file_info "$SCRIPTS_DIR/dashboard_views.sql")
FILE_CSV_CUST=$(check_file_info "$EXPORT_DIR/customer_spending.csv")
FILE_CSV_GENRE=$(check_file_info "$EXPORT_DIR/genre_revenue.csv")
FILE_CSV_EMP=$(check_file_info "$EXPORT_DIR/employee_sales.csv")

# 3. Inspect Database State (Views)
# We use sqlite3 to query metadata and data since verifier can't exec_in_env

# Function to safely get query result or null
db_query() {
    local sql="$1"
    local res=$(sqlite3 "$DB_PATH" "$sql" 2>/dev/null)
    if [ -z "$res" ]; then echo "null"; else echo "$res"; fi
}

# Check if views exist
VIEW_CUST_EXISTS=$(db_query "SELECT count(*) FROM sqlite_master WHERE type='view' AND name='v_customer_spending';")
VIEW_GENRE_EXISTS=$(db_query "SELECT count(*) FROM sqlite_master WHERE type='view' AND name='v_genre_revenue';")
VIEW_EMP_EXISTS=$(db_query "SELECT count(*) FROM sqlite_master WHERE type='view' AND name='v_employee_sales_summary';")

# Get Row Counts (if views exist)
COUNT_CUST=0
COUNT_GENRE=0
COUNT_EMP=0
[ "$VIEW_CUST_EXISTS" -eq 1 ] && COUNT_CUST=$(db_query "SELECT count(*) FROM v_customer_spending;")
[ "$VIEW_GENRE_EXISTS" -eq 1 ] && COUNT_GENRE=$(db_query "SELECT count(*) FROM v_genre_revenue;")
[ "$VIEW_EMP_EXISTS" -eq 1 ] && COUNT_EMP=$(db_query "SELECT count(*) FROM v_employee_sales_summary;")

# Validation Checks (Top values)
# Top spender: CustomerName|TotalSpending
TOP_SPENDER=$(db_query "SELECT CustomerName || '|' || TotalSpending FROM v_customer_spending ORDER BY TotalSpending DESC LIMIT 1;" || echo "")
# Top Genre: GenreName
TOP_GENRE=$(db_query "SELECT GenreName FROM v_genre_revenue ORDER BY TotalRevenue DESC LIMIT 1;" || echo "")
# Total Revenue Sum Check (Employee view)
TOTAL_REV_CHECK=$(db_query "SELECT ROUND(SUM(TotalRevenue),0) FROM v_employee_sales_summary;" || echo 0)

# 4. Check DBeaver Connection
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
HAS_CHINOOK_CONN="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    # Simple grep check for the connection name
    if grep -qi "\"name\": \"Chinook\"" "$DBEAVER_CONFIG"; then
        HAS_CHINOOK_CONN="true"
    fi
fi

# 5. Build JSON Result
cat > /tmp/task_result.json <<EOF
{
  "timestamp": $(date +%s),
  "db_connection_exists": $HAS_CHINOOK_CONN,
  "views": {
    "v_customer_spending": {
      "exists": $([ "$VIEW_CUST_EXISTS" -eq 1 ] && echo true || echo false),
      "row_count": $COUNT_CUST,
      "top_spender_raw": "$TOP_SPENDER"
    },
    "v_genre_revenue": {
      "exists": $([ "$VIEW_GENRE_EXISTS" -eq 1 ] && echo true || echo false),
      "row_count": $COUNT_GENRE,
      "top_genre": "$TOP_GENRE"
    },
    "v_employee_sales_summary": {
      "exists": $([ "$VIEW_EMP_EXISTS" -eq 1 ] && echo true || echo false),
      "row_count": $COUNT_EMP,
      "total_revenue_sum": ${TOTAL_REV_CHECK:-0}
    }
  },
  "files": {
    "sql_script": $FILE_SCRIPT,
    "csv_customer": $FILE_CSV_CUST,
    "csv_genre": $FILE_CSV_GENRE,
    "csv_employee": $FILE_CSV_EMP
  }
}
EOF

# Safe copy to output for verifier reading
chmod 666 /tmp/task_result.json
echo "Result JSON generated."
cat /tmp/task_result.json