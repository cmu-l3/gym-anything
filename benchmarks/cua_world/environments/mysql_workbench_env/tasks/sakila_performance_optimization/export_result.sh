#!/bin/bash
# Export script for sakila_performance_optimization task

echo "=== Exporting Sakila Performance Optimization Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Helper: count standalone single-column indexes on a given table.column
# A standalone index means: the column is SEQ_IN_INDEX=1 AND the index has no other columns (total count=1)
count_standalone_index() {
    local tbl=$1
    local col=$2
    mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT COUNT(DISTINCT s1.INDEX_NAME)
        FROM STATISTICS s1
        WHERE s1.TABLE_SCHEMA='sakila' AND s1.TABLE_NAME='${tbl}'
          AND s1.COLUMN_NAME='${col}' AND s1.SEQ_IN_INDEX=1
          AND s1.INDEX_NAME != 'PRIMARY'
          AND (
            SELECT COUNT(*) FROM STATISTICS s2
            WHERE s2.TABLE_SCHEMA='sakila' AND s2.TABLE_NAME='${tbl}'
              AND s2.INDEX_NAME = s1.INDEX_NAME
          ) = 1
    " 2>/dev/null | tr -d '[:space:]'
}

# Check standalone index on rental.customer_id
IDX_RENTAL_CUSTOMER=$(count_standalone_index rental customer_id)
IDX_RENTAL_CUSTOMER=${IDX_RENTAL_CUSTOMER:-0}

# Check standalone index on payment.rental_id
IDX_PAYMENT_RENTAL=$(count_standalone_index payment rental_id)
IDX_PAYMENT_RENTAL=${IDX_PAYMENT_RENTAL:-0}

# Check standalone index on inventory.film_id
IDX_INVENTORY_FILM=$(count_standalone_index inventory film_id)
IDX_INVENTORY_FILM=${IDX_INVENTORY_FILM:-0}

# Check v_monthly_revenue view exists
VIEW_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_monthly_revenue'
" 2>/dev/null)
VIEW_EXISTS=${VIEW_EXISTS:-0}

# Check view has expected columns (payment_year, payment_month, total_revenue)
VIEW_HAS_YEAR=0
VIEW_HAS_MONTH=0
VIEW_HAS_REVENUE=0
if [ "$VIEW_EXISTS" -gt 0 ]; then
    COLS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT COLUMN_NAME FROM COLUMNS
        WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_monthly_revenue'
    " 2>/dev/null)
    echo "$COLS" | grep -qi "year" && VIEW_HAS_YEAR=1
    echo "$COLS" | grep -qi "month" && VIEW_HAS_MONTH=1
    echo "$COLS" | grep -qi "revenue\|amount\|total" && VIEW_HAS_REVENUE=1
fi

# Check sp_monthly_revenue procedure exists
PROC_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM ROUTINES
    WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_NAME='sp_monthly_revenue'
    AND ROUTINE_TYPE='PROCEDURE'
" 2>/dev/null)
PROC_EXISTS=${PROC_EXISTS:-0}

# Check CSV export
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0
OUTPUT_FILE="/home/ga/Documents/exports/monthly_revenue_2005.csv"
if [ -f "$OUTPUT_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

cat > /tmp/perf_opt_result.json << EOF
{
    "idx_rental_customer_restored": $IDX_RENTAL_CUSTOMER,
    "idx_payment_rental_restored": $IDX_PAYMENT_RENTAL,
    "idx_inventory_film_restored": $IDX_INVENTORY_FILM,
    "view_exists": $VIEW_EXISTS,
    "view_has_year_col": $VIEW_HAS_YEAR,
    "view_has_month_col": $VIEW_HAS_MONTH,
    "view_has_revenue_col": $VIEW_HAS_REVENUE,
    "proc_exists": $PROC_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result: idx_rental=${IDX_RENTAL_CUSTOMER} idx_payment=${IDX_PAYMENT_RENTAL} idx_inventory=${IDX_INVENTORY_FILM} view=${VIEW_EXISTS} proc=${PROC_EXISTS} csv=${CSV_EXISTS}(${CSV_ROWS} rows)"
echo "=== Export Complete ==="
