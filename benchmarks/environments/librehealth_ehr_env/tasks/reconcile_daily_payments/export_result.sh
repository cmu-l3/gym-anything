#!/bin/bash
echo "=== Exporting Reconcile Daily Payments Result ==="

source /workspace/scripts/task_utils.sh

# Load task context
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TARGET_PID=$(cat /tmp/target_pid 2>/dev/null || echo "0")
TARGET_FNAME=$(cat /tmp/target_fname 2>/dev/null || echo "Unknown")
TARGET_LNAME=$(cat /tmp/target_lname 2>/dev/null || echo "Unknown")
INITIAL_PAYMENT_COUNT=$(cat /tmp/initial_payment_count 2>/dev/null || echo "0")

OUTPUT_PDF="/home/ga/Desktop/day_sheet.pdf"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Database for Payment Record
# We look for a record in ar_activity:
# - Linked to the correct PID
# - Amount = 40.00
# - Type contains "cash" (case insensitive)
# - Created AFTER task start

# Note: post_time is usually a datetime string. We compare it against FROM_UNIXTIME($TASK_START)
DB_QUERY="SELECT count(*) FROM ar_activity WHERE pid='${TARGET_PID}' AND pay_amount >= 39.99 AND pay_amount <= 40.01 AND LOWER(pay_type) LIKE '%cash%' AND post_time >= FROM_UNIXTIME(${TASK_START})"
PAYMENT_FOUND_COUNT=$(librehealth_query "$DB_QUERY" 2>/dev/null || echo "0")

# 3. Check for Output PDF
PDF_EXISTS="false"
PDF_SIZE="0"
PDF_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PDF" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$OUTPUT_PDF" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c %Y "$OUTPUT_PDF" 2>/dev/null || echo "0")
    
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        PDF_CREATED_DURING_TASK="true"
    fi
    
    # Prepare PDF for export (verification logic runs on host)
    cp "$OUTPUT_PDF" /tmp/day_sheet_export.pdf
    chmod 644 /tmp/day_sheet_export.pdf
fi

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "target_pid": "$TARGET_PID",
    "target_fname": "$TARGET_FNAME",
    "target_lname": "$TARGET_LNAME",
    "payment_found_in_db": $([ "$PAYMENT_FOUND_COUNT" -gt 0 ] && echo "true" || echo "false"),
    "payment_records_count": $PAYMENT_FOUND_COUNT,
    "pdf_exists": $PDF_EXISTS,
    "pdf_created_during_task": $PDF_CREATED_DURING_TASK,
    "pdf_size_bytes": $PDF_SIZE,
    "pdf_path_in_container": "/tmp/day_sheet_export.pdf",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. DB Records found: $PAYMENT_FOUND_COUNT"
cat /tmp/task_result.json