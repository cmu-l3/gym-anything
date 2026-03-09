#!/bin/bash
# Export script for Cookie Inventory Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Cookie Inventory Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 1. Check for CSV Export
CSV_PATH="$EXPORT_DIR/cookie_inventory.csv"
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_HAS_COOKIE_HEADERS="false"
CSV_ROW_COUNT=0
CSV_HAS_CRAWLER_TEST="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_CREATED_DURING_TASK="true"
        
        # Analyze content
        HEADER=$(head -1 "$CSV_PATH" 2>/dev/null || echo "")
        
        # Check for standard cookie export headers
        if echo "$HEADER" | grep -qi "Cookie Name" && echo "$HEADER" | grep -qi "Cookie Value"; then
            CSV_HAS_COOKIE_HEADERS="true"
        fi
        
        # Count data rows (excluding header)
        TOTAL_LINES=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
        if [ "$TOTAL_LINES" -gt 0 ]; then
            CSV_ROW_COUNT=$((TOTAL_LINES - 1))
        fi
        
        # Check for target domain data
        if grep -qi "crawler-test.com" "$CSV_PATH" 2>/dev/null; then
            CSV_HAS_CRAWLER_TEST="true"
        fi
        
        # Copy for verification
        cp "$CSV_PATH" /tmp/verify_cookies.csv
    fi
fi

# 2. Check for Summary Report
REPORT_PATH="$REPORTS_DIR/cookie_summary.txt"
REPORT_EXISTS="false"
REPORT_CONTENT_LENGTH=0

if [ -f "$REPORT_PATH" ]; then
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_EXISTS="true"
        REPORT_CONTENT_LENGTH=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
        cp "$REPORT_PATH" /tmp/verify_report.txt
    fi
fi

# 3. Check App State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Write result JSON
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_created_during_task": "$CSV_CREATED_DURING_TASK" == "true",
    "csv_has_cookie_headers": "$CSV_HAS_COOKIE_HEADERS" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_has_crawler_test": "$CSV_HAS_CRAWLER_TEST" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_length": $REPORT_CONTENT_LENGTH,
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/cookie_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/cookie_audit_result.json")
PYEOF

cat /tmp/cookie_audit_result.json
echo "=== Export Complete ==="