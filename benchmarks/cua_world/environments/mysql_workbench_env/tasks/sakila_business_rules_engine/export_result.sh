#!/bin/bash
# Export script for sakila_business_rules_engine task

echo "=== Exporting Task Result ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPECTED_ACTIVE_COUNT=$(cat /tmp/expected_active_count 2>/dev/null || echo "584")

# Helper function to check object existence in Information Schema
check_object() {
    local type=$1
    local name=$2
    local table="ROUTINES"
    local schema_col="ROUTINE_SCHEMA"
    local name_col="ROUTINE_NAME"
    local type_col="ROUTINE_TYPE"
    
    if [ "$type" == "VIEW" ]; then
        table="VIEWS"
        schema_col="TABLE_SCHEMA"
        name_col="TABLE_NAME"
        type_col=""
    elif [ "$type" == "TABLE" ]; then
        table="TABLES"
        schema_col="TABLE_SCHEMA"
        name_col="TABLE_NAME"
        type_col="TABLE_TYPE" # We'll handle this differently for tables usually
    fi

    local query="SELECT COUNT(*) FROM information_schema.$table WHERE $schema_col = 'sakila' AND $name_col = '$name'"
    if [ -n "$type_col" ] && [ "$type" != "TABLE" ]; then
        query="$query AND $type_col = '$type'"
    fi
    
    mysql -u root -p'GymAnything#2024' -N -e "$query" 2>/dev/null
}

# 1. Check Function Existence
FN_LATE_DAYS_EXISTS=$(check_object "FUNCTION" "fn_rental_late_days")
FN_LATE_FEE_EXISTS=$(check_object "FUNCTION" "fn_late_fee")
FN_TIER_EXISTS=$(check_object "FUNCTION" "fn_customer_tier")
FN_POP_EXISTS=$(check_object "FUNCTION" "fn_film_popularity")

# 2. Check View Existence
VIEW_EXISTS=$(check_object "VIEW" "v_customer_billing_summary")

# 3. Check Table Existence and Count
TABLE_EXISTS=$(mysql -u root -p'GymAnything#2024' -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='customer_billing_report'" 2>/dev/null)
TABLE_ROW_COUNT=0
if [ "$TABLE_EXISTS" -eq "1" ]; then
    TABLE_ROW_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer_billing_report" 2>/dev/null || echo "0")
fi

# 4. Logical Verification (Run the functions to verify correctness)
# We select specific test cases known in standard Sakila data
# Customer 148: ELEANOR HUNT (46 rentals -> GOLD)
# Customer 318: BRIAN WYMAN (27 rentals -> SILVER)
# Customer 61: KATHERINE RIVERA (14 rentals -> BRONZE)
# Rental 1185: Returned late (Rental Date: 2005-06-14, Return: 2005-06-23, Duration: 6, Late: 3 days)

LOGIC_TESTS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
SELECT CONCAT(
    IFNULL(fn_customer_tier(148), 'NULL'), '|',
    IFNULL(fn_customer_tier(318), 'NULL'), '|',
    IFNULL(fn_customer_tier(61), 'NULL'), '|',
    IFNULL(fn_rental_late_days(1185), 'NULL'), '|',
    IFNULL(fn_late_fee(1185), 'NULL')
);" 2>/dev/null || echo "ERROR|ERROR|ERROR|ERROR|ERROR")

IFS='|' read -r RES_TIER_GOLD RES_TIER_SILVER RES_TIER_BRONZE RES_LATE_DAYS RES_LATE_FEE <<< "$LOGIC_TESTS"

# 5. Check View Columns
VIEW_COLUMNS=""
if [ "$VIEW_EXISTS" -eq "1" ]; then
    VIEW_COLUMNS=$(mysql -u root -p'GymAnything#2024' -N -e "
        SELECT GROUP_CONCAT(COLUMN_NAME) 
        FROM information_schema.COLUMNS 
        WHERE TABLE_SCHEMA = 'sakila' AND TABLE_NAME = 'v_customer_billing_summary'
    " 2>/dev/null)
fi

# 6. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/customer_billing_report.csv"
CSV_EXISTS="false"
CSV_MTIME=0
CSV_SIZE=0
CSV_LINES=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH")
    CSV_SIZE=$(stat -c %s "$CSV_PATH")
    CSV_LINES=$(wc -l < "$CSV_PATH")
fi

# Construct JSON result
cat > /tmp/task_result.json << EOF
{
    "fn_rental_late_days_exists": ${FN_LATE_DAYS_EXISTS:-0},
    "fn_late_fee_exists": ${FN_LATE_FEE_EXISTS:-0},
    "fn_customer_tier_exists": ${FN_TIER_EXISTS:-0},
    "fn_film_popularity_exists": ${FN_POP_EXISTS:-0},
    "view_exists": ${VIEW_EXISTS:-0},
    "table_exists": ${TABLE_EXISTS:-0},
    "table_row_count": ${TABLE_ROW_COUNT:-0},
    "expected_row_count": ${EXPECTED_ACTIVE_COUNT:-0},
    "view_columns": "${VIEW_COLUMNS}",
    "logic_check": {
        "tier_gold": "${RES_TIER_GOLD}",
        "tier_silver": "${RES_TIER_SILVER}",
        "tier_bronze": "${RES_TIER_BRONZE}",
        "late_days_1185": "${RES_LATE_DAYS}",
        "late_fee_1185": "${RES_LATE_FEE}"
    },
    "csv_exists": ${CSV_EXISTS},
    "csv_mtime": ${CSV_MTIME},
    "csv_lines": ${CSV_LINES},
    "task_start_time": ${TASK_START}
}
EOF

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json