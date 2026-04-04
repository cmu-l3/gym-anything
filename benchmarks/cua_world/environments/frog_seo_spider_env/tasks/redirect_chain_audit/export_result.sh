#!/bin/bash
# Export script for Redirect Chain Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Redirect Chain Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
REPORT_PATH="$REPORTS_DIR/redirect_report.txt"

REDIRECT_CSV=""
REDIRECT_ROW_COUNT=0
HAS_STATUS_CODE_COL="false"
HAS_REDIRECT_URL_COL="false"
HAS_3XX_DATA="false"
REDIRECT_TYPE_301="false"
REDIRECT_TYPE_302="false"
TARGET_DOMAIN_IN_CSV="false"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_COUNTS="false"
REPORT_HAS_REDIRECT_TYPES="false"
SF_RUNNING="false"
WINDOW_INFO=""

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider\|crawler-test" | head -1 || echo "")

# Find redirect CSV in exports directory
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            SAMPLE=$(head -10 "$csv_file" 2>/dev/null || echo "")

            # Identify a redirect/response codes CSV
            # Look for columns: "Status Code" + "Redirect URL"
            # OR filenames suggesting redirect export
            IS_REDIRECT_CSV="false"
            if echo "$HEADER" | grep -qi "Status Code\|Redirect URL\|Status"; then
                IS_REDIRECT_CSV="true"
            fi
            if echo "$SAMPLE" | grep -qE "30[1-9]|redirect\|Redirect"; then
                IS_REDIRECT_CSV="true"
            fi

            if [ "$IS_REDIRECT_CSV" = "true" ]; then
                REDIRECT_CSV="$csv_file"

                # Check for required columns
                if echo "$HEADER" | grep -qi "Status Code"; then
                    HAS_STATUS_CODE_COL="true"
                fi
                if echo "$HEADER" | grep -qi "Redirect URL\|Redirect"; then
                    HAS_REDIRECT_URL_COL="true"
                fi

                # Check for actual 3xx data
                if grep -qE ",30[1-9],|,30[1-9]$" "$csv_file" 2>/dev/null; then
                    HAS_3XX_DATA="true"
                fi
                if grep -q ",301," "$csv_file" 2>/dev/null || grep -q ",301$" "$csv_file" 2>/dev/null; then
                    REDIRECT_TYPE_301="true"
                fi
                if grep -q ",302," "$csv_file" 2>/dev/null || grep -q ",302$" "$csv_file" 2>/dev/null; then
                    REDIRECT_TYPE_302="true"
                fi

                # Count rows with 3xx status
                REDIRECT_ROW_COUNT=$(grep -cE ",30[0-9]," "$csv_file" 2>/dev/null || echo "0")

                # Check domain
                if grep -qi "crawler-test.com" "$csv_file" 2>/dev/null; then
                    TARGET_DOMAIN_IN_CSV="true"
                fi
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# Check for text report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    # Check if report has count numbers (digits)
    if grep -qE "[0-9]+" "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_COUNTS="true"
    fi
    # Check if report mentions redirect types
    if grep -qiE "301|302|307|308|redirect chain|permanent|temporary|hop" "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_REDIRECT_TYPES="true"
    fi
fi

NEW_CSV_COUNT=$(find "$EXPORT_DIR" -name "*.csv" -newer /tmp/task_start_time -type f 2>/dev/null | wc -l || echo "0")

# Write result JSON using Python
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "new_csv_count": $NEW_CSV_COUNT,
    "redirect_csv_found": len("$REDIRECT_CSV") > 0,
    "redirect_csv_path": "$REDIRECT_CSV",
    "has_status_code_column": "$HAS_STATUS_CODE_COL" == "true",
    "has_redirect_url_column": "$HAS_REDIRECT_URL_COL" == "true",
    "has_3xx_data": "$HAS_3XX_DATA" == "true",
    "redirect_row_count": $REDIRECT_ROW_COUNT,
    "has_301": "$REDIRECT_TYPE_301" == "true",
    "has_302": "$REDIRECT_TYPE_302" == "true",
    "target_domain_in_csv": "$TARGET_DOMAIN_IN_CSV" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_path": "$REPORT_PATH",
    "report_size_bytes": $REPORT_SIZE,
    "report_has_counts": "$REPORT_HAS_COUNTS" == "true",
    "report_has_redirect_types": "$REPORT_HAS_REDIRECT_TYPES" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/redirect_chain_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/redirect_chain_audit_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
