#!/bin/bash
echo "=== Exporting Patent Research Results ==="

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PDF_PATH="/home/ga/Documents/Patents/US5255452.pdf"
SUMMARY_PATH="/home/ga/Documents/Patents/patent_summary.txt"

# 1. Check PDF status
PDF_EXISTS="false"
PDF_SIZE="0"
PDF_CREATED_DURING_TASK="false"

if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_PATH")
    PDF_MTIME=$(stat -c %Y "$PDF_PATH")
    if [ "$PDF_MTIME" -ge "$TASK_START" ]; then
        PDF_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Summary status and content
SUMMARY_EXISTS="false"
SUMMARY_CONTENT=""
SUMMARY_CREATED_DURING_TASK="false"

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_CONTENT=$(cat "$SUMMARY_PATH" | tr '\n' ' ' | sed 's/"/\\"/g')
    SUMMARY_MTIME=$(stat -c %Y "$SUMMARY_PATH")
    if [ "$SUMMARY_MTIME" -ge "$TASK_START" ]; then
        SUMMARY_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Browser History for Google Patents visit
# We use a temporary copy of the history DB to avoid locking issues
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
HISTORY_VISIT_FOUND="false"

if [ -f "$HISTORY_DB" ]; then
    cp "$HISTORY_DB" /tmp/history_copy.sqlite
    # Check for visit to patents.google.com/patent/US5255452 or similar
    VISIT_COUNT=$(sqlite3 /tmp/history_copy.sqlite "SELECT count(*) FROM urls WHERE url LIKE '%patents.google.com/patent/US5255452%' OR url LIKE '%patents.google.com%5255452%';" 2>/dev/null || echo "0")
    if [ "$VISIT_COUNT" -gt 0 ]; then
        HISTORY_VISIT_FOUND="true"
    fi
    rm -f /tmp/history_copy.sqlite
fi

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "pdf_fresh": $PDF_CREATED_DURING_TASK,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_fresh": $SUMMARY_CREATED_DURING_TASK,
    "summary_content": "$SUMMARY_CONTENT",
    "history_visit_found": $HISTORY_VISIT_FOUND,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="