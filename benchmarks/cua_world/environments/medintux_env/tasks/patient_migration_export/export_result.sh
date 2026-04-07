#!/bin/bash
echo "=== Exporting Task Results ==="

# Define paths
DB_NAME="DrTuxTest"
TABLE_NAME="patient_export"
CSV_FILE="/home/ga/Documents/patient_export.csv"
REPORT_FILE="/home/ga/Documents/migration_summary.txt"
RESULT_JSON="/tmp/task_result.json"

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if Table Exists and Get Schema
echo "Checking database table..."
TABLE_INFO=$(mysql -u root $DB_NAME -e "DESCRIBE $TABLE_NAME;" 2>/dev/null || echo "not_found")
TABLE_EXISTS="false"
COLUMNS_LIST="[]"
ROW_COUNT=0

if [ "$TABLE_INFO" != "not_found" ]; then
    TABLE_EXISTS="true"
    # Extract column names as JSON array
    COLUMNS_LIST=$(mysql -u root $DB_NAME -N -e "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='$TABLE_NAME';" | python3 -c 'import sys, json; print(json.dumps([l.strip() for l in sys.stdin]))')
    # Get row count
    ROW_COUNT=$(mysql -u root $DB_NAME -N -e "SELECT COUNT(*) FROM $TABLE_NAME;" 2>/dev/null || echo 0)
    
    # Export a sample of data for integrity checking (First 3 rows)
    SAMPLE_DATA=$(mysql -u root $DB_NAME -e "SELECT * FROM $TABLE_NAME LIMIT 3;" | python3 -c 'import sys, csv, json; reader=csv.DictReader(sys.stdin, delimiter="\t"); print(json.dumps(list(reader)))')
else
    SAMPLE_DATA="[]"
fi

# 2. Check CSV File
echo "Checking CSV file..."
CSV_EXISTS="false"
CSV_HEADER="[]"
CSV_ROW_COUNT=0
CSV_CREATED_DURING_TASK="false"

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    # Read header
    CSV_HEADER=$(head -n 1 "$CSV_FILE" | python3 -c 'import sys, csv, json; reader=csv.reader(sys.stdin); print(json.dumps(next(reader)))' 2>/dev/null || echo "[]")
    # Count rows (excluding header)
    CSV_ROW_COUNT=$(($(wc -l < "$CSV_FILE") - 1))
    
    # Check creation time
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)
    FILE_TIME=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo 0)
    if [ "$FILE_TIME" -ge "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Report File
echo "Checking summary report..."
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | head -c 1000) # Read first 1000 chars
fi

# 4. Load Ground Truth
GROUND_TRUTH="{}"
if [ -f "/tmp/ground_truth.json" ]; then
    GROUND_TRUTH=$(cat /tmp/ground_truth.json)
fi

# 5. Assemble JSON Result
# Using python to safely construct JSON to avoid escaping issues
python3 -c "
import json
import os

result = {
    'table_exists': $TABLE_EXISTS,
    'table_columns': $COLUMNS_LIST,
    'table_row_count': int('$ROW_COUNT'),
    'table_sample': $SAMPLE_DATA,
    'csv_exists': $CSV_EXISTS,
    'csv_header': $CSV_HEADER,
    'csv_row_count': int('$CSV_ROW_COUNT'),
    'csv_created_during_task': $CSV_CREATED_DURING_TASK,
    'report_exists': $REPORT_EXISTS,
    'report_content': '''$REPORT_CONTENT''',
    'ground_truth': $GROUND_TRUTH
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f)
"

# Set permissions so verifier can read it
chmod 666 "$RESULT_JSON"
echo "Export complete. Result saved to $RESULT_JSON"