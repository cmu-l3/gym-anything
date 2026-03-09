#!/bin/bash
# Export script for sakila_bi_analytics task

echo "=== Exporting Sakila BI Analytics Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check v_film_revenue_by_store view
VIEW1_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_film_revenue_by_store'
" 2>/dev/null)
VIEW1_EXISTS=${VIEW1_EXISTS:-0}

# Check v_film_revenue_by_store has expected columns
VIEW1_HAS_FILM_ID=0
VIEW1_HAS_STORE_ID=0
VIEW1_HAS_RENTAL_COUNT=0
VIEW1_HAS_REVENUE=0
if [ "$VIEW1_EXISTS" -gt 0 ]; then
    COLS1=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT COLUMN_NAME FROM COLUMNS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_film_revenue_by_store'
    " 2>/dev/null)
    echo "$COLS1" | grep -qi "film_id\|film" && VIEW1_HAS_FILM_ID=1
    echo "$COLS1" | grep -qi "store_id\|store" && VIEW1_HAS_STORE_ID=1
    echo "$COLS1" | grep -qi "rental" && VIEW1_HAS_RENTAL_COUNT=1
    echo "$COLS1" | grep -qi "revenue\|amount\|total" && VIEW1_HAS_REVENUE=1
fi

# Check v_customer_lifetime_value view
VIEW2_EXISTS=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_customer_lifetime_value'
" 2>/dev/null)
VIEW2_EXISTS=${VIEW2_EXISTS:-0}

# Check v_customer_lifetime_value has expected columns
VIEW2_HAS_CUSTOMER_ID=0
VIEW2_HAS_NAME=0
VIEW2_HAS_TOTAL=0
VIEW2_ROW_COUNT=0
if [ "$VIEW2_EXISTS" -gt 0 ]; then
    COLS2=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT COLUMN_NAME FROM COLUMNS WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_customer_lifetime_value'
    " 2>/dev/null)
    echo "$COLS2" | grep -qi "customer_id\|customer" && VIEW2_HAS_CUSTOMER_ID=1
    echo "$COLS2" | grep -qi "name\|first\|last" && VIEW2_HAS_NAME=1
    echo "$COLS2" | grep -qi "spent\|amount\|total\|revenue" && VIEW2_HAS_TOTAL=1

    VIEW2_ROW_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*) FROM v_customer_lifetime_value;
    " 2>/dev/null)
    VIEW2_ROW_COUNT=${VIEW2_ROW_COUNT:-0}
fi

# Check reporter user exists
USER_EXISTS=$(mysql -u root -p'GymAnything#2024' -N -e "
    SELECT COUNT(*) FROM mysql.user WHERE User='reporter' AND Host='localhost'
" 2>/dev/null)
USER_EXISTS=${USER_EXISTS:-0}

# Check reporter has SELECT privilege on views
REPORTER_HAS_VIEW1=0
REPORTER_HAS_VIEW2=0
if [ "$USER_EXISTS" -gt 0 ]; then
    # Check table-level privileges
    PRIV_V1=$(mysql -u root -p'GymAnything#2024' -N -e "
        SELECT COUNT(*) FROM information_schema.TABLE_PRIVILEGES
        WHERE GRANTEE='''reporter''@''localhost''' AND TABLE_SCHEMA='sakila'
        AND TABLE_NAME='v_film_revenue_by_store' AND PRIVILEGE_TYPE='SELECT'
    " 2>/dev/null)
    REPORTER_HAS_VIEW1=${PRIV_V1:-0}

    PRIV_V2=$(mysql -u root -p'GymAnything#2024' -N -e "
        SELECT COUNT(*) FROM information_schema.TABLE_PRIVILEGES
        WHERE GRANTEE='''reporter''@''localhost''' AND TABLE_SCHEMA='sakila'
        AND TABLE_NAME='v_customer_lifetime_value' AND PRIVILEGE_TYPE='SELECT'
    " 2>/dev/null)
    REPORTER_HAS_VIEW2=${PRIV_V2:-0}

    # Also check schema-level SELECT privilege (covers all views)
    if [ "$REPORTER_HAS_VIEW1" -eq 0 ]; then
        SCHEMA_PRIV=$(mysql -u root -p'GymAnything#2024' -N -e "
            SELECT COUNT(*) FROM information_schema.SCHEMA_PRIVILEGES
            WHERE GRANTEE='''reporter''@''localhost''' AND TABLE_SCHEMA='sakila'
            AND PRIVILEGE_TYPE='SELECT'
        " 2>/dev/null)
        [ "${SCHEMA_PRIV:-0}" -gt 0 ] && REPORTER_HAS_VIEW1=1 && REPORTER_HAS_VIEW2=1
    fi
fi

# Check CSV export
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0
OUTPUT_FILE="/home/ga/Documents/exports/customer_lifetime_value.csv"
if [ -f "$OUTPUT_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

cat > /tmp/bi_analytics_result.json << EOF
{
    "view1_exists": $VIEW1_EXISTS,
    "view1_has_film_id": $VIEW1_HAS_FILM_ID,
    "view1_has_store_id": $VIEW1_HAS_STORE_ID,
    "view1_has_rental_count": $VIEW1_HAS_RENTAL_COUNT,
    "view1_has_revenue": $VIEW1_HAS_REVENUE,
    "view2_exists": $VIEW2_EXISTS,
    "view2_has_customer_id": $VIEW2_HAS_CUSTOMER_ID,
    "view2_has_name": $VIEW2_HAS_NAME,
    "view2_has_total": $VIEW2_HAS_TOTAL,
    "view2_row_count": $VIEW2_ROW_COUNT,
    "user_exists": $USER_EXISTS,
    "reporter_has_view1_priv": $REPORTER_HAS_VIEW1,
    "reporter_has_view2_priv": $REPORTER_HAS_VIEW2,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result: view1=${VIEW1_EXISTS} view2=${VIEW2_EXISTS}(${VIEW2_ROW_COUNT}rows) user=${USER_EXISTS} priv1=${REPORTER_HAS_VIEW1} priv2=${REPORTER_HAS_VIEW2} csv=${CSV_EXISTS}(${CSV_ROWS}rows)"
echo "=== Export Complete ==="
