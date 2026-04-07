#!/bin/bash
# Export script for sakila_data_integrity_constraints task

echo "=== Exporting Sakila Data Integrity Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- DATABASE VERIFICATION ---

# 1. Check if bad data was fixed
REMAINING_BAD_FILMS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM film WHERE rental_duration <= 0")
REMAINING_BAD_PAYMENTS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM payment WHERE amount < 0")

# 2. Check for Constraints
# MySQL 8.0 stores CHECK constraints in information_schema.CHECK_CONSTRAINTS
HAS_FILM_CONSTRAINT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM TABLE_CONSTRAINTS 
    WHERE CONSTRAINT_SCHEMA='sakila' 
    AND TABLE_NAME='film' 
    AND CONSTRAINT_TYPE='CHECK' 
    AND CONSTRAINT_NAME='chk_rental_duration'
")

HAS_PAYMENT_CONSTRAINT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM TABLE_CONSTRAINTS 
    WHERE CONSTRAINT_SCHEMA='sakila' 
    AND TABLE_NAME='payment' 
    AND CONSTRAINT_TYPE='CHECK' 
    AND CONSTRAINT_NAME='chk_payment_amount'
")

# 3. Check for Column and Data Population
HAS_PRICE_CATEGORY=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM COLUMNS 
    WHERE TABLE_SCHEMA='sakila' 
    AND TABLE_NAME='film' 
    AND COLUMN_NAME='price_category' 
    AND COLUMN_TYPE LIKE 'enum%'
")

# Check if column is populated (count NULLs)
PRICE_CATEGORY_NULLS=9999
if [ "$HAS_PRICE_CATEGORY" -gt 0 ]; then
    PRICE_CATEGORY_NULLS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM film WHERE price_category IS NULL")
fi

# Verify logic spot check
# rental_rate 0.99 -> Budget
# rental_rate 2.99 -> Standard
# rental_rate 4.99 -> Premium
PRICE_LOGIC_CORRECT="false"
if [ "$HAS_PRICE_CATEGORY" -gt 0 ]; then
    CHECK_BUDGET=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM film WHERE rental_rate < 1.50 AND price_category != 'Budget'")
    CHECK_STANDARD=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM film WHERE rental_rate >= 1.50 AND rental_rate < 3.50 AND price_category != 'Standard'")
    CHECK_PREMIUM=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM film WHERE rental_rate >= 3.50 AND price_category != 'Premium'")
    
    if [ "$CHECK_BUDGET" -eq 0 ] && [ "$CHECK_STANDARD" -eq 0 ] && [ "$CHECK_PREMIUM" -eq 0 ]; then
        PRICE_LOGIC_CORRECT="true"
    fi
fi

# 4. Check Stored Function
HAS_FUNCTION=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM ROUTINES 
    WHERE ROUTINE_SCHEMA='sakila' 
    AND ROUTINE_NAME='fn_customer_lifetime_value' 
    AND ROUTINE_TYPE='FUNCTION'
")

FUNCTION_LOGIC_CORRECT="false"
if [ "$HAS_FUNCTION" -gt 0 ]; then
    # Calculate expected value for customer 1
    EXPECTED_VAL=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT SUM(amount) FROM payment WHERE customer_id=1")
    # Call function
    ACTUAL_VAL=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT fn_customer_lifetime_value(1)")
    
    # Compare (allow slight float diff, though DECIMAL should be exact)
    if [ "$EXPECTED_VAL" = "$ACTUAL_VAL" ] && [ -n "$ACTUAL_VAL" ]; then
        FUNCTION_LOGIC_CORRECT="true"
    fi
fi

# 5. Check Export File
CSV_PATH="/home/ga/Documents/exports/data_integrity_report.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$CSV_PATH")
    CSV_ROWS=$(wc -l < "$CSV_PATH")
    # Adjust for header
    CSV_ROWS=$((CSV_ROWS - 1))
fi

# Create Result JSON
cat > /tmp/integrity_result.json << EOF
{
    "task_start": $TASK_START,
    "remaining_bad_films": ${REMAINING_BAD_FILMS:-0},
    "remaining_bad_payments": ${REMAINING_BAD_PAYMENTS:-0},
    "has_film_constraint": ${HAS_FILM_CONSTRAINT:-0},
    "has_payment_constraint": ${HAS_PAYMENT_CONSTRAINT:-0},
    "has_price_category": ${HAS_PRICE_CATEGORY:-0},
    "price_category_nulls": ${PRICE_CATEGORY_NULLS:-9999},
    "price_logic_correct": $PRICE_LOGIC_CORRECT,
    "has_function": ${HAS_FUNCTION:-0},
    "function_logic_correct": $FUNCTION_LOGIC_CORRECT,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME
}
EOF

echo "Export completed. Result:"
cat /tmp/integrity_result.json