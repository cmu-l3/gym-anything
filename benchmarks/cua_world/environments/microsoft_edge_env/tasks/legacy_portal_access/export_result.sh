#!/bin/bash
# export_result.sh - Export results for Legacy Portal Access task

echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Data Paths
OUTPUT_FILE="/home/ga/Desktop/manifest_code.txt"
GROUND_TRUTH_FILE="/var/lib/legacy_portal/secret_code.txt"
SERVER_LOG="/tmp/server_access.log"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Read File Content
OUTPUT_CONTENT=""
FILE_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE" | tr -d '\n\r ')
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# 4. Read Ground Truth
GROUND_TRUTH=$(cat "$GROUND_TRUTH_FILE" 2>/dev/null | tr -d '\n\r ')

# 5. Check Server Logs for Successful Spoofing
# We look for a 200 OK response logic in the python script which logs the UA
SUCCESSFUL_ACCESS="false"
USED_IE_UA="false"

if [ -f "$SERVER_LOG" ]; then
    if grep -qE "MSIE|Trident" "$SERVER_LOG"; then
        USED_IE_UA="true"
    fi
    # If the file exists and has content, it means the server was hit. 
    # The logic in verifier will strictly check the code match.
fi

# 6. Check Browser History (Did they actually use the browser?)
# We copy the history DB to temp to avoid locks
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
HISTORY_VISIT="false"

if [ -f "$HISTORY_DB" ]; then
    cp "$HISTORY_DB" /tmp/history_check.sqlite
    VISIT_COUNT=$(sqlite3 /tmp/history_check.sqlite "SELECT count(*) FROM urls WHERE url LIKE '%localhost:8000%';" 2>/dev/null || echo "0")
    if [ "$VISIT_COUNT" -gt "0" ]; then
        HISTORY_VISIT="true"
    fi
    rm -f /tmp/history_check.sqlite
fi

# 7. Check for Screenshot Evidence
SCREENSHOT_EXISTS="false"
# The agent might have saved a specific screenshot as requested in instructions, 
# or we just rely on the final state screenshot.
# Task instructions say: "Take a screenshot of the successfully loaded portal page."
# We look for any NEW png file on Desktop or Documents
EVIDENCE_SCREENSHOT=$(find /home/ga/Desktop /home/ga/Documents -name "*.png" -newermt "@$TASK_START_TIME" 2>/dev/null | head -n 1)
if [ -n "$EVIDENCE_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 8. Create JSON Result
JSON_FILE="/tmp/task_result.json"
cat > "$JSON_FILE" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_MODIFIED_DURING_TASK,
    "extracted_code": "$OUTPUT_CONTENT",
    "ground_truth_code": "$GROUND_TRUTH",
    "server_log_shows_ie": $USED_IE_UA,
    "browser_history_visit": $HISTORY_VISIT,
    "evidence_screenshot_exists": $SCREENSHOT_EXISTS,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Cleanup
# Kill the server
SERVER_PID=$(cat /tmp/server_pid.txt 2>/dev/null)
if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
fi

echo "Export complete. Result saved to $JSON_FILE"
cat "$JSON_FILE"