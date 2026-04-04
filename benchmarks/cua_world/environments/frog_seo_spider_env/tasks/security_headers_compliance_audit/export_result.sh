#!/bin/bash
# Export script for Security Headers Compliance Audit

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting Security Headers Audit Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define paths and variables
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
CSV_FILE="$EXPORT_DIR/security_audit.csv"
REPORT_FILE="$REPORTS_DIR/security_headers_summary.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 3. Analyze CSV Export
CSV_EXISTS="false"
CSV_MODIFIED_AFTER_START="false"
CSV_HAS_HTTPS="false"
CSV_HAS_SECURITY_COLS="false"
CSV_ROW_COUNT=0

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    
    # Check modification time
    FILE_EPOCH=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED_AFTER_START="true"
    fi
    
    # Count rows (minus header)
    LINE_COUNT=$(wc -l < "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$LINE_COUNT" -gt 1 ]; then
        CSV_ROW_COUNT=$((LINE_COUNT - 1))
    fi

    # Read header and a sample of content
    HEADER=$(head -1 "$CSV_FILE" 2>/dev/null || echo "")
    CONTENT_SAMPLE=$(head -10 "$CSV_FILE" 2>/dev/null || echo "")

    # Check for HTTPS usage in URLs
    if echo "$CONTENT_SAMPLE" | grep -q "https://"; then
        CSV_HAS_HTTPS="true"
    fi

    # Check for Security-specific columns or data
    # Security exports usually contain headers like "HSTS", "X-Frame-Options" 
    # OR if it's a filter export, the data might imply it.
    # We check for common security header names in the file content.
    if grep -qiE "X-Frame-Options|X-Content-Type-Options|Strict-Transport-Security|Referrer-Policy|Security" "$CSV_FILE"; then
        CSV_HAS_SECURITY_COLS="true"
    fi
fi

# 4. Analyze Text Report
REPORT_EXISTS="false"
REPORT_MODIFIED_AFTER_START="false"
REPORT_HAS_COUNTS="false"
REPORT_HAS_HSTS="false"
REPORT_CONTENT_LENGTH=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    
    # Check modification time
    FILE_EPOCH=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_MODIFIED_AFTER_START="true"
    fi

    REPORT_CONTENT_LENGTH=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    
    # Check for numbers (counts)
    if grep -qE "[0-9]+" "$REPORT_FILE"; then
        REPORT_HAS_COUNTS="true"
    fi
    
    # Check for HSTS mention
    if grep -qi "HSTS" "$REPORT_FILE" || grep -qi "Strict-Transport-Security" "$REPORT_FILE"; then
        REPORT_HAS_HSTS="true"
    fi
fi

# 5. Check App Status
APP_RUNNING="false"
if is_screamingfrog_running; then
    APP_RUNNING="true"
fi

# 6. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "app_running": $APP_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_modified_after_start": $CSV_MODIFIED_AFTER_START,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_has_https": $CSV_HAS_HTTPS,
    "csv_has_security_cols": $CSV_HAS_SECURITY_COLS,
    "report_exists": $REPORT_EXISTS,
    "report_modified_after_start": $REPORT_MODIFIED_AFTER_START,
    "report_content_length": $REPORT_CONTENT_LENGTH,
    "report_has_counts": $REPORT_HAS_COUNTS,
    "report_has_hsts": $REPORT_HAS_HSTS
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="