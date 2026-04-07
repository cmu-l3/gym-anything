#!/bin/bash
# export_result.sh - Export results for Accessibility Compliance Audit

echo "=== Exporting Accessibility Audit Result ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Report File
REPORT_PATH="/home/ga/Desktop/audit_remediation.txt"
REPORT_EXISTS="false"
REPORT_MODIFIED_DURING_TASK="false"
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED_DURING_TASK="true"
    fi
fi

# 4. Check Browser History (Did they visit the local file?)
# We look for the file path in the history DB
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
FILE_VISITED="false"

if [ -f "$HISTORY_DB" ]; then
    # Copy DB to temp to avoid locks
    cp "$HISTORY_DB" /tmp/history_check.sqlite
    
    # Check for file URI
    VISIT_COUNT=$(sqlite3 /tmp/history_check.sqlite "SELECT COUNT(*) FROM urls WHERE url LIKE 'file:///home/ga/Documents/city_portal_staging.html';" 2>/dev/null || echo "0")
    
    if [ "$VISIT_COUNT" -gt "0" ]; then
        FILE_VISITED="true"
    fi
    rm -f /tmp/history_check.sqlite
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_modified_during_task": $REPORT_MODIFIED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "target_file_visited": $FILE_VISITED,
    "report_path": "$REPORT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Safe copy to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json