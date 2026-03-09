#!/bin/bash
# Export script for Competitive Benchmark List Crawl task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

# Trap errors to ensure result file is always created
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final_state.png

# 2. Define Paths
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
EXPECTED_CSV="$EXPORT_DIR/competitive_benchmark.csv"
EXPECTED_REPORT="$REPORTS_DIR/competitive_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 3. Analyze CSV Export
CSV_EXISTS="false"
CSV_MODIFIED_IN_TASK="false"
DOMAINS_FOUND_IN_CSV=""
ROW_COUNT=0
HAS_STANDARD_COLUMNS="false"

# Check the specific file, or find the most recent CSV if specific name not used
TARGET_CSV=""
if [ -f "$EXPECTED_CSV" ]; then
    TARGET_CSV="$EXPECTED_CSV"
else
    # Fallback: check for newest CSV in folder
    TARGET_CSV=$(ls -t "$EXPORT_DIR"/*.csv 2>/dev/null | head -1)
fi

if [ -n "$TARGET_CSV" ] && [ -f "$TARGET_CSV" ]; then
    CSV_EXISTS="true"
    
    # Check modification time
    FILE_EPOCH=$(stat -c %Y "$TARGET_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED_IN_TASK="true"
    fi

    # Check content (domains)
    # We look for the domains in the file content
    DOMAINS_FOUND_LIST=()
    if grep -q "books.toscrape.com" "$TARGET_CSV"; then DOMAINS_FOUND_LIST+=("books.toscrape.com"); fi
    if grep -q "quotes.toscrape.com" "$TARGET_CSV"; then DOMAINS_FOUND_LIST+=("quotes.toscrape.com"); fi
    if grep -q "crawler-test.com" "$TARGET_CSV"; then DOMAINS_FOUND_LIST+=("crawler-test.com"); fi
    
    # Join array with comma
    DOMAINS_FOUND_IN_CSV=$(IFS=,; echo "${DOMAINS_FOUND_LIST[*]}")

    # Count rows (excluding header)
    ROW_COUNT=$(($(wc -l < "$TARGET_CSV") - 1))

    # Check for standard columns (Address, Status Code, Title 1)
    HEADER=$(head -1 "$TARGET_CSV")
    if echo "$HEADER" | grep -q "Address" && echo "$HEADER" | grep -q "Status Code"; then
        HAS_STANDARD_COLUMNS="true"
    fi
fi

# 4. Analyze Text Report
REPORT_EXISTS="false"
REPORT_MODIFIED_IN_TASK="false"
REPORT_SIZE=0
REPORT_CONTENT_CHECK="false"
REPORT_HAS_NUMBERS="false"
REPORT_HAS_RECOMMENDATIONS="false"

if [ -f "$EXPECTED_REPORT" ]; then
    REPORT_EXISTS="true"
    
    # Check modification time
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_REPORT" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_MODIFIED_IN_TASK="true"
    fi

    REPORT_SIZE=$(stat -c %s "$EXPECTED_REPORT" 2>/dev/null || echo "0")

    # Content checks
    CONTENT=$(cat "$EXPECTED_REPORT" | tr '[:upper:]' '[:lower:]')
    
    # Check for domain mentions
    if echo "$CONTENT" | grep -q "books.toscrape" && \
       echo "$CONTENT" | grep -q "quotes.toscrape" && \
       echo "$CONTENT" | grep -q "crawler-test"; then
        REPORT_CONTENT_CHECK="true"
    fi

    # Check for numbers (metrics)
    if grep -qE "[0-9]" "$EXPECTED_REPORT"; then
        REPORT_HAS_NUMBERS="true"
    fi

    # Check for recommendation keywords
    if echo "$CONTENT" | grep -qE "recommend|suggest|should|improve|optimize|fix|issue"; then
        REPORT_HAS_RECOMMENDATIONS="true"
    fi
fi

# 5. Check App Status
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 6. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << PYEOF > "$TEMP_JSON"
import json
import time

result = {
    "sf_running": $SF_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_modified_in_task": $CSV_MODIFIED_IN_TASK,
    "csv_path": "$TARGET_CSV",
    "domains_found": "$DOMAINS_FOUND_IN_CSV".split(",") if "$DOMAINS_FOUND_IN_CSV" else [],
    "row_count": $ROW_COUNT,
    "has_standard_columns": $HAS_STANDARD_COLUMNS,
    "report_exists": $REPORT_EXISTS,
    "report_modified_in_task": $REPORT_MODIFIED_IN_TASK,
    "report_size": $REPORT_SIZE,
    "report_mentions_all_domains": $REPORT_CONTENT_CHECK,
    "report_has_numbers": $REPORT_HAS_NUMBERS,
    "report_has_recommendations": $REPORT_HAS_RECOMMENDATIONS,
    "timestamp": int(time.time())
}
print(json.dumps(result, indent=2))
PYEOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="