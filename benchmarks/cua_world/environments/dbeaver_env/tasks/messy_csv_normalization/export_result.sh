#!/bin/bash
echo "=== Exporting Messy CSV Normalization Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
SCRIPT_PATH="/home/ga/Documents/scripts/clean_import.sql"
CSV_PATH="/home/ga/Documents/imports/legacy_sales_dump.csv"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Initialize results
TABLE_EXISTS="false"
ROW_COUNT_MATCH="false"
ACTUAL_ROW_COUNT=0
EXPECTED_ROW_COUNT=$(count_csv_lines "$CSV_PATH")
COLUMNS_CORRECT="false"
DATE_FORMAT_CORRECT="false"
AMOUNT_NUMERIC="false"
IDS_EXTRACTED="false"
SUM_MATCH="false"
SCRIPT_EXISTS="false"
SCRIPT_CONTENT=""

# Check Script
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH" | head -c 500) # capture start of script
fi

# Database Verification using SQLite3
if [ -f "$DB_PATH" ]; then
    # 1. Check Table Existence
    if sqlite3 "$DB_PATH" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='clean_sales';" | grep -q "1"; then
        TABLE_EXISTS="true"
        
        # 2. Check Row Count
        ACTUAL_ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM clean_sales;")
        if [ "$ACTUAL_ROW_COUNT" -eq "$EXPECTED_ROW_COUNT" ]; then
            ROW_COUNT_MATCH="true"
        fi
        
        # 3. Check Schema/Columns
        SCHEMA_INFO=$(sqlite3 "$DB_PATH" "PRAGMA table_info(clean_sales);")
        if echo "$SCHEMA_INFO" | grep -qi "SaleId" && \
           echo "$SCHEMA_INFO" | grep -qi "SaleDate" && \
           echo "$SCHEMA_INFO" | grep -qi "CustomerId" && \
           echo "$SCHEMA_INFO" | grep -qi "SaleAmount"; then
            COLUMNS_CORRECT="true"
        fi
        
        # 4. Check Date Format (YYYY-MM-DD)
        # Sample 5 dates and check regex
        SAMPLE_DATES=$(sqlite3 "$DB_PATH" "SELECT SaleDate FROM clean_sales LIMIT 5;")
        if echo "$SAMPLE_DATES" | grep -E -q "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"; then
            # Ensure it's not the old format
            if ! echo "$SAMPLE_DATES" | grep -q "/"; then
                DATE_FORMAT_CORRECT="true"
            fi
        fi
        
        # 5. Check Amounts (Numeric)
        # We check if SUM works and matches expected
        EXPECTED_SUM=$(cat /tmp/expected_sum.txt 2>/dev/null || echo "0")
        ACTUAL_SUM=$(sqlite3 "$DB_PATH" "SELECT SUM(SaleAmount) FROM clean_sales;" 2>/dev/null || echo "0")
        
        # Calculate difference (using python for float math)
        SUM_MATCH=$(python3 -c "
try:
    exp = float('$EXPECTED_SUM')
    act = float('$ACTUAL_SUM')
    if abs(exp - act) < 1.0: # Tolerance for rounding
        print('true')
    else:
        print('false')
except:
    print('false')
")

        # Check if type is effectively numeric (not a string with $)
        SAMPLE_AMOUNTS=$(sqlite3 "$DB_PATH" "SELECT SaleAmount FROM clean_sales LIMIT 5;")
        if ! echo "$SAMPLE_AMOUNTS" | grep -q "\\$"; then
            AMOUNT_NUMERIC="true"
        fi
        
        # 6. Check ID Extraction
        # We verify that CustomerId contains only integers, not brackets or text
        SAMPLE_IDS=$(sqlite3 "$DB_PATH" "SELECT CustomerId FROM clean_sales LIMIT 5;")
        if echo "$SAMPLE_IDS" | grep -E -q "^[0-9]+$"; then
            IDS_EXTRACTED="true"
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "table_exists": $TABLE_EXISTS,
    "actual_row_count": $ACTUAL_ROW_COUNT,
    "expected_row_count": $EXPECTED_ROW_COUNT,
    "row_count_match": $ROW_COUNT_MATCH,
    "columns_correct": $COLUMNS_CORRECT,
    "date_format_correct": $DATE_FORMAT_CORRECT,
    "amount_numeric": $AMOUNT_NUMERIC,
    "ids_extracted": $IDS_EXTRACTED,
    "sum_match": $SUM_MATCH,
    "script_exists": $SCRIPT_EXISTS,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="