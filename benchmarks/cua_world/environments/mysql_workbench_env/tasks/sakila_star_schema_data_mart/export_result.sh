#!/bin/bash
# Export script for sakila_star_schema_data_mart task

echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Database Verification Helper ---
# Executes SQL and returns result. If error, returns -1 or empty string.
run_sql() {
    mysql -u root -p'GymAnything#2024' sakila_mart -N -e "$1" 2>/dev/null
}

run_meta_sql() {
    mysql -u root -p'GymAnything#2024' information_schema -N -e "$1" 2>/dev/null
}

echo "Collecting verification data..."

# 1. Check Database Existence
DB_EXISTS=$(mysql -u root -p'GymAnything#2024' -e "SHOW DATABASES LIKE 'sakila_mart';" 2>/dev/null | wc -l)

# 2. Check Table Structures (Column Counts)
DIM_DATE_COLS=$(run_meta_sql "SELECT COUNT(*) FROM COLUMNS WHERE TABLE_SCHEMA='sakila_mart' AND TABLE_NAME='dim_date'")
DIM_CUST_COLS=$(run_meta_sql "SELECT COUNT(*) FROM COLUMNS WHERE TABLE_SCHEMA='sakila_mart' AND TABLE_NAME='dim_customer'")
DIM_FILM_COLS=$(run_meta_sql "SELECT COUNT(*) FROM COLUMNS WHERE TABLE_SCHEMA='sakila_mart' AND TABLE_NAME='dim_film'")
DIM_STORE_COLS=$(run_meta_sql "SELECT COUNT(*) FROM COLUMNS WHERE TABLE_SCHEMA='sakila_mart' AND TABLE_NAME='dim_store'")
FACT_RENTAL_COLS=$(run_meta_sql "SELECT COUNT(*) FROM COLUMNS WHERE TABLE_SCHEMA='sakila_mart' AND TABLE_NAME='fact_rental'")

# 3. Check Row Counts
DIM_DATE_ROWS=$(run_sql "SELECT COUNT(*) FROM dim_date" || echo "0")
DIM_CUST_ROWS=$(run_sql "SELECT COUNT(*) FROM dim_customer" || echo "0")
DIM_FILM_ROWS=$(run_sql "SELECT COUNT(*) FROM dim_film" || echo "0")
DIM_STORE_ROWS=$(run_sql "SELECT COUNT(*) FROM dim_store" || echo "0")
FACT_RENTAL_ROWS=$(run_sql "SELECT COUNT(*) FROM fact_rental" || echo "0")

# 4. Check View Existence and Logic
VIEW_EXISTS=$(run_meta_sql "SELECT COUNT(*) FROM VIEWS WHERE TABLE_SCHEMA='sakila_mart' AND TABLE_NAME='v_monthly_store_performance'")
VIEW_ROWS=0
VIEW_REVENUE_SUM=0

if [ "$VIEW_EXISTS" -eq 1 ]; then
    VIEW_ROWS=$(run_sql "SELECT COUNT(*) FROM v_monthly_store_performance" || echo "0")
    # Check if revenue aggregation happened (sum of total_revenue > 0)
    # We check if the column exists first implicitly by running the query
    VIEW_REVENUE_SUM=$(run_sql "SELECT COALESCE(SUM(total_revenue), 0) FROM v_monthly_store_performance" || echo "0")
fi

# 5. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/monthly_store_performance.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_SIZE=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Count rows (minus header)
    TOTAL_LINES=$(wc -l < "$CSV_PATH")
    CSV_ROWS=$((TOTAL_LINES - 1))
fi

# Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "db_exists": $((DB_EXISTS > 0 ? 1 : 0)),
    "dim_date_cols": ${DIM_DATE_COLS:-0},
    "dim_date_rows": ${DIM_DATE_ROWS:-0},
    "dim_cust_cols": ${DIM_CUST_COLS:-0},
    "dim_cust_rows": ${DIM_CUST_ROWS:-0},
    "dim_film_cols": ${DIM_FILM_COLS:-0},
    "dim_film_rows": ${DIM_FILM_ROWS:-0},
    "dim_store_cols": ${DIM_STORE_COLS:-0},
    "dim_store_rows": ${DIM_STORE_ROWS:-0},
    "fact_rental_cols": ${FACT_RENTAL_COLS:-0},
    "fact_rental_rows": ${FACT_RENTAL_ROWS:-0},
    "view_exists": ${VIEW_EXISTS:-0},
    "view_rows": ${VIEW_ROWS:-0},
    "view_revenue_sum": ${VIEW_REVENUE_SUM:-0},
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

echo "Verification data saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="