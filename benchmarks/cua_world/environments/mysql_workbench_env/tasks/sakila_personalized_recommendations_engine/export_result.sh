#!/bin/bash
# Export script for sakila_personalized_recommendations_engine

echo "=== Exporting Recommendation Engine Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Database Credentials
DB_USER="root"
DB_PASS="GymAnything#2024"
DB_NAME="sakila"

# 1. Check if Table Exists
TABLE_EXISTS=$(mysql -u $DB_USER -p$DB_PASS -N -e "
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema='$DB_NAME' AND table_name='customer_recommendations';
" 2>/dev/null)
TABLE_EXISTS=${TABLE_EXISTS:-0}

# 2. Check if Procedure Exists
PROC_EXISTS=$(mysql -u $DB_USER -p$DB_PASS -N -e "
    SELECT COUNT(*) FROM information_schema.routines 
    WHERE routine_schema='$DB_NAME' AND routine_name='sp_generate_recommendations';
" 2>/dev/null)
PROC_EXISTS=${PROC_EXISTS:-0}

# 3. Get Row Count
ROW_COUNT=0
if [ "$TABLE_EXISTS" -eq 1 ]; then
    ROW_COUNT=$(mysql -u $DB_USER -p$DB_PASS -N -e "SELECT COUNT(*) FROM $DB_NAME.customer_recommendations;" 2>/dev/null)
fi
ROW_COUNT=${ROW_COUNT:-0}

# 4. CONSTRAINT CHECK: Unseen Films
# Count how many recommended films were ALREADY in the customer's rental history
# Should be 0 if logic is correct.
UNSEEN_VIOLATIONS=0
if [ "$TABLE_EXISTS" -eq 1 ]; then
    UNSEEN_VIOLATIONS=$(mysql -u $DB_USER -p$DB_PASS -N -e "
        SELECT COUNT(*)
        FROM $DB_NAME.customer_recommendations cr
        JOIN $DB_NAME.rental r ON cr.customer_id = r.customer_id
        JOIN $DB_NAME.inventory i ON r.inventory_id = i.inventory_id
        WHERE cr.film_id = i.film_id;
    " 2>/dev/null)
fi
UNSEEN_VIOLATIONS=${UNSEEN_VIOLATIONS:-0}

# 5. LOGIC CHECK: Favorite Category Alignment
# We pick Customer 1 (MARY SMITH).
# Step A: Find her actual favorite category using SQL
MARY_TOP_CATEGORY=$(mysql -u $DB_USER -p$DB_PASS -N -e "
    SELECT c.category_id
    FROM $DB_NAME.rental r
    JOIN $DB_NAME.inventory i ON r.inventory_id = i.inventory_id
    JOIN $DB_NAME.film_category fc ON i.film_id = fc.film_id
    JOIN $DB_NAME.category c ON fc.category_id = c.category_id
    WHERE r.customer_id = 1
    GROUP BY c.category_id, c.name
    ORDER BY COUNT(*) DESC, c.name ASC
    LIMIT 1;
" 2>/dev/null)

# Step B: Count how many of her recommendations match this category
MARY_MATCHING_RECS=0
if [ "$TABLE_EXISTS" -eq 1 ] && [ -n "$MARY_TOP_CATEGORY" ]; then
    MARY_MATCHING_RECS=$(mysql -u $DB_USER -p$DB_PASS -N -e "
        SELECT COUNT(*)
        FROM $DB_NAME.customer_recommendations cr
        JOIN $DB_NAME.film_category fc ON cr.film_id = fc.film_id
        WHERE cr.customer_id = 1 AND fc.category_id = $MARY_TOP_CATEGORY;
    " 2>/dev/null)
fi
MARY_MATCHING_RECS=${MARY_MATCHING_RECS:-0}

# 6. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/recommendations_batch_01.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || echo "0")
    # Count lines, subtract header
    RAW_LINES=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_ROWS=$((RAW_LINES - 1))
fi

# 7. Check if Workbench is running
APP_RUNNING=$(pgrep -f "mysql-workbench" > /dev/null && echo "true" || echo "false")

# Compile results to JSON
cat > /tmp/task_result.json << EOF
{
    "table_exists": $TABLE_EXISTS,
    "proc_exists": $PROC_EXISTS,
    "row_count": $ROW_COUNT,
    "unseen_violations": $UNSEEN_VIOLATIONS,
    "mary_top_category_id": "${MARY_TOP_CATEGORY}",
    "mary_matching_recs": $MARY_MATCHING_RECS,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start_time": $TASK_START,
    "app_running": $APP_RUNNING
}
EOF

echo "Export completed. JSON result generated."
cat /tmp/task_result.json