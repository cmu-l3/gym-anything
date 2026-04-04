#!/bin/bash
# Export script for chinook_data_migration task

echo "=== Exporting Chinook Data Migration Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check if NULL BillingAddress issues were fixed
NULL_BILLING_REMAINING=$(mysql -u root -p'GymAnything#2024' chinook -N -e "
    SELECT COUNT(*) FROM Invoice WHERE BillingAddress IS NULL;
" 2>/dev/null)
NULL_BILLING_REMAINING=${NULL_BILLING_REMAINING:-99}

# Check if wrong UnitPrice issues were fixed
WRONG_UNITPRICE_REMAINING=$(mysql -u root -p'GymAnything#2024' chinook -N -e "
    SELECT COUNT(*) FROM InvoiceLine il
    JOIN Track t ON il.TrackId = t.TrackId
    WHERE ABS(il.UnitPrice - t.UnitPrice) > 0.001;
" 2>/dev/null)
WRONG_UNITPRICE_REMAINING=${WRONG_UNITPRICE_REMAINING:-99}

# Check view v_sales_by_genre exists
VIEW_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS
    WHERE TABLE_SCHEMA='chinook' AND TABLE_NAME='v_sales_by_genre'
" 2>/dev/null)
VIEW_EXISTS=${VIEW_EXISTS:-0}

# Check view has reasonable content (genre count)
VIEW_ROW_COUNT=0
if [ "$VIEW_EXISTS" -gt 0 ]; then
    VIEW_ROW_COUNT=$(mysql -u root -p'GymAnything#2024' chinook -N -e "
        SELECT COUNT(*) FROM v_sales_by_genre;
    " 2>/dev/null)
    VIEW_ROW_COUNT=${VIEW_ROW_COUNT:-0}
fi

# Check index idx_invoiceline_trackid exists
INDEX_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM STATISTICS
    WHERE TABLE_SCHEMA='chinook' AND TABLE_NAME='InvoiceLine'
    AND COLUMN_NAME='TrackId' AND INDEX_NAME != 'PRIMARY'
" 2>/dev/null)
INDEX_EXISTS=${INDEX_EXISTS:-0}

# Check CSV export
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0
OUTPUT_FILE="/home/ga/Documents/exports/chinook_genre_sales.csv"
if [ -f "$OUTPUT_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

# Get initial injected counts for reference
INITIAL_NULL=$(cat /tmp/initial_null_billing 2>/dev/null || echo "15")
INITIAL_WRONG=$(cat /tmp/initial_wrong_unitprice 2>/dev/null || echo "3")

cat > /tmp/chinook_migration_result.json << EOF
{
    "null_billing_remaining": $NULL_BILLING_REMAINING,
    "null_billing_initial": $INITIAL_NULL,
    "wrong_unitprice_remaining": $WRONG_UNITPRICE_REMAINING,
    "wrong_unitprice_initial": $INITIAL_WRONG,
    "view_exists": $VIEW_EXISTS,
    "view_row_count": $VIEW_ROW_COUNT,
    "index_exists": $INDEX_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result: null_billing_remaining=${NULL_BILLING_REMAINING} wrong_price_remaining=${WRONG_UNITPRICE_REMAINING} view=${VIEW_EXISTS}(${VIEW_ROW_COUNT}rows) index=${INDEX_EXISTS} csv=${CSV_EXISTS}(${CSV_ROWS}rows)"
echo "=== Export Complete ==="
