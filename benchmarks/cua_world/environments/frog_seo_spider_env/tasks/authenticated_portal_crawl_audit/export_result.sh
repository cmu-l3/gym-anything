#!/bin/bash
# Export script for Authenticated Portal Crawl Audit

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting Authenticated Crawl Result ==="

# Capture final state
take_screenshot /tmp/task_final.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 1. Identify the exported CSV
# We look for the most recently modified CSV in the export directory
TARGET_CSV=""
LATEST_EPOCH=0

if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            if [ "$FILE_EPOCH" -gt "$LATEST_EPOCH" ]; then
                LATEST_EPOCH=$FILE_EPOCH
                TARGET_CSV="$csv_file"
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 2. Analyze CSV Content (if found)
CSV_FOUND="false"
HAS_LOGOUT_LINK="false"
ROW_COUNT=0
DOMAIN_MATCH="false"

if [ -n "$TARGET_CSV" ] && [ -f "$TARGET_CSV" ]; then
    CSV_FOUND="true"
    echo "Found export file: $TARGET_CSV"
    
    # Check for logout link (proof of authentication)
    # The URL is typically http://quotes.toscrape.com/logout/
    if grep -q "/logout/" "$TARGET_CSV"; then
        HAS_LOGOUT_LINK="true"
        echo "SUCCESS: Found '/logout/' link in export"
    fi

    # Check domain
    if grep -q "quotes.toscrape.com" "$TARGET_CSV"; then
        DOMAIN_MATCH="true"
    fi

    # Count rows (excluding header)
    ROW_COUNT=$(($(wc -l < "$TARGET_CSV") - 1))
    
    # Copy to /tmp for verification extraction
    cp "$TARGET_CSV" /tmp/auth_crawl_export.csv
    chmod 644 /tmp/auth_crawl_export.csv
fi

# 3. Check Report File
REPORT_FOUND="false"
REPORT_PATH="$REPORTS_DIR/auth_success_report.txt"
if [ -f "$REPORT_PATH" ]; then
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_FOUND="true"
        cp "$REPORT_PATH" /tmp/auth_report.txt
        chmod 644 /tmp/auth_report.txt
    fi
fi

# 4. Check App State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sf_running": $SF_RUNNING,
    "csv_found": $CSV_FOUND,
    "csv_path": "$TARGET_CSV",
    "has_logout_link": $HAS_LOGOUT_LINK,
    "domain_match": $DOMAIN_MATCH,
    "row_count": $ROW_COUNT,
    "report_found": $REPORT_FOUND,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="