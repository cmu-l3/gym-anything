#!/bin/bash
# Export script for Code Bloat Ratio Audit task

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting Code Bloat Audit Result ==="

# 1. Capture final state
take_screenshot /tmp/task_final_screenshot.png
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 2. Define paths
EXPORT_FILE="/home/ga/Documents/SEO/exports/code_bloat_data.csv"
REPORT_FILE="/home/ga/Documents/SEO/reports/bloat_analysis.txt"

# 3. Analyze CSV Export
CSV_EXISTS="false"
CSV_MODIFIED_AFTER_START="false"
HAS_RATIO_COLUMN="false"
HAS_TARGET_DOMAIN="false"
ROW_COUNT=0
COLUMNS_FOUND=""

if [ -f "$EXPORT_FILE" ]; then
    CSV_EXISTS="true"
    
    # Check modification time
    FILE_EPOCH=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED_AFTER_START="true"
    fi

    # Analyze content
    # Read header
    HEADER=$(head -1 "$EXPORT_FILE" 2>/dev/null || echo "")
    COLUMNS_FOUND=$(echo "$HEADER" | cut -c 1-100) # Save start of header for debug
    
    # Check for specific column: "Text to Code Ratio"
    # Note: CSV headers might be quoted "Text to Code Ratio"
    if echo "$HEADER" | grep -qi "Text to Code Ratio"; then
        HAS_RATIO_COLUMN="true"
    fi

    # Check for target domain in content
    if grep -qi "books.toscrape.com" "$EXPORT_FILE"; then
        HAS_TARGET_DOMAIN="true"
    fi

    # Count data rows (excluding header)
    TOTAL_LINES=$(wc -l < "$EXPORT_FILE" 2>/dev/null || echo "0")
    ROW_COUNT=$((TOTAL_LINES - 1))
fi

# 4. Analyze Text Report
REPORT_EXISTS="false"
REPORT_MODIFIED_AFTER_START="false"
REPORT_SIZE=0
REPORT_HAS_NUMBERS="false"
REPORT_HAS_URLS="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    
    # Check modification time
    FILE_EPOCH=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_MODIFIED_AFTER_START="true"
    fi
    
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Check content for numbers (ratios) and URLs
    if grep -qE "[0-9]+(\.[0-9]+)?%?" "$REPORT_FILE"; then
        REPORT_HAS_NUMBERS="true"
    fi
    if grep -qi "http" "$REPORT_FILE" || grep -qi "toscrape" "$REPORT_FILE"; then
        REPORT_HAS_URLS="true"
    fi
fi

# 5. Check App State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 6. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << PYEOF > "$TEMP_JSON"
import json

result = {
    "sf_running": $SF_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_modified": $CSV_MODIFIED_AFTER_START,
    "has_ratio_column": $HAS_RATIO_COLUMN,
    "has_target_domain": $HAS_TARGET_DOMAIN,
    "row_count": $ROW_COUNT,
    "csv_columns_snippet": "$COLUMNS_FOUND",
    "report_exists": $REPORT_EXISTS,
    "report_modified": $REPORT_MODIFIED_AFTER_START,
    "report_size": $REPORT_SIZE,
    "report_has_numbers": $REPORT_HAS_NUMBERS,
    "report_has_urls": $REPORT_HAS_URLS,
    "timestamp": "$(date -Iseconds)"
}

print(json.dumps(result, indent=2))
PYEOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="