#!/bin/bash
# Export script for Non-Standard Redirect Audit task

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting Non-Standard Redirect Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

META_REFRESH_FILE="$EXPORT_DIR/meta_refresh_audit.csv"
JS_REDIRECT_FILE="$EXPORT_DIR/js_redirect_audit.csv"
REPORT_FILE="$REPORTS_DIR/redirect_remediation_summary.txt"

# Initialize result variables
SF_RUNNING="false"
WINDOW_INFO=""
META_FILE_EXISTS="false"
META_FILE_VALID="false"
META_ROW_COUNT=0
JS_FILE_EXISTS="false"
JS_FILE_VALID="false"
JS_ROW_COUNT=0
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_SIZE=0

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# 1. Verify Meta Refresh CSV
if [ -f "$META_REFRESH_FILE" ]; then
    FILE_EPOCH=$(stat -c %Y "$META_REFRESH_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        META_FILE_EXISTS="true"
        # Check content
        if grep -qi "crawler-test.com" "$META_REFRESH_FILE"; then
            META_FILE_VALID="true"
        fi
        # Count data rows (subtract header)
        TOTAL_LINES=$(wc -l < "$META_REFRESH_FILE" 2>/dev/null || echo "0")
        if [ "$TOTAL_LINES" -gt 1 ]; then
            META_ROW_COUNT=$((TOTAL_LINES - 1))
        fi
    fi
fi

# 2. Verify JS Redirect CSV
if [ -f "$JS_REDIRECT_FILE" ]; then
    FILE_EPOCH=$(stat -c %Y "$JS_REDIRECT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        JS_FILE_EXISTS="true"
        # Check content
        if grep -qi "crawler-test.com" "$JS_REDIRECT_FILE"; then
            JS_FILE_VALID="true"
        fi
        # Count data rows
        TOTAL_LINES=$(wc -l < "$JS_REDIRECT_FILE" 2>/dev/null || echo "0")
        if [ "$TOTAL_LINES" -gt 1 ]; then
            JS_ROW_COUNT=$((TOTAL_LINES - 1))
        fi
    fi
fi

# 3. Verify Report
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Check for keywords and basic content length
    if [ "$REPORT_SIZE" -gt 50 ]; then
        if grep -qiE "meta refresh|javascript|301" "$REPORT_FILE"; then
            REPORT_VALID="true"
        fi
    fi
fi

# Write result JSON using Python for safety
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING == "true",
    "window_info": """$WINDOW_INFO""",
    "meta_refresh": {
        "exists": "$META_FILE_EXISTS" == "true",
        "valid_content": "$META_FILE_VALID" == "true",
        "row_count": $META_ROW_COUNT
    },
    "js_redirect": {
        "exists": "$JS_FILE_EXISTS" == "true",
        "valid_content": "$JS_FILE_VALID" == "true",
        "row_count": $JS_ROW_COUNT
    },
    "report": {
        "exists": "$REPORT_EXISTS" == "true",
        "valid_content": "$REPORT_VALID" == "true",
        "size_bytes": $REPORT_SIZE
    },
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export Complete ==="