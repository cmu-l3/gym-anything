#!/bin/bash
echo "=== Exporting export_legacy_sales_report result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Task metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_PATH="/home/ga/Documents/last_month_sales.csv"
EXPECTED_MONTH_PREFIX=$(date -d "$(date +%Y-%m-01) -1 month" +%Y-%m) # e.g., 2023-02

# Check output file
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
CSV_HEADERS=""
CSV_SAMPLE_DATA=""
HAS_TARGET_MONTH_DATA="false"

if [ -f "$EXPECTED_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPECTED_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPECTED_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read headers (first line)
    # Remove BOM if present and quotes
    CSV_HEADERS=$(head -n 1 "$EXPECTED_PATH" | tr -d '\357\273\277' | tr -d '"')
    
    # Read sample data (lines 2-6)
    CSV_SAMPLE_DATA=$(sed -n '2,6p' "$EXPECTED_PATH")
    
    # Check for target month in sample data
    # We look for the YYYY-MM string in the file content
    if grep -q "$EXPECTED_MONTH_PREFIX" "$EXPECTED_PATH"; then
        HAS_TARGET_MONTH_DATA="true"
    fi
fi

# Helper: Check if download happened but file wasn't moved
DOWNLOAD_FOUND="false"
DOWNLOAD_PATH=""
POSSIBLE_DOWNLOAD=$(find /home/ga/Downloads -name "sales_by_date*.csv" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)

if [ -n "$POSSIBLE_DOWNLOAD" ]; then
    DOWNLOAD_FOUND="true"
    DOWNLOAD_PATH="$POSSIBLE_DOWNLOAD"
fi

# Escape for JSON
CSV_HEADERS_ESC=$(json_escape "$CSV_HEADERS")
# We just take the first 100 chars of sample data to avoid JSON issues
CSV_SAMPLE_ESC=$(json_escape "${CSV_SAMPLE_DATA:0:200}")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/export_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$EXPECTED_PATH",
    "file_size": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "headers": "$CSV_HEADERS_ESC",
    "sample_data": "$CSV_SAMPLE_ESC",
    "has_target_month_data": $HAS_TARGET_MONTH_DATA,
    "expected_month_prefix": "$EXPECTED_MONTH_PREFIX",
    "download_found_in_downloads": $DOWNLOAD_FOUND,
    "download_path": "$DOWNLOAD_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="