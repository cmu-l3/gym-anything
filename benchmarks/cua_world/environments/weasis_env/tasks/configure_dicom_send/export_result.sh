#!/bin/bash
echo "=== Exporting configure_dicom_send result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Safely kill the PACS receiver daemon
pkill -f storescp

# 1. Analyze Received Files
RECEIVER_DIR="/tmp/pacs_received"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TOTAL_FILES=$(find "$RECEIVER_DIR" -type f 2>/dev/null | wc -l || echo "0")
NEW_FILES=0

for f in "$RECEIVER_DIR"/*; do
    if [ -f "$f" ]; then
        MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            NEW_FILES=$((NEW_FILES+1))
        fi
    fi
done

# 2. Analyze DICOM Network Protocol Logs
LOG_FILE="/tmp/storescp.log"
ASSOC_COUNT=$(grep -c -i "Association Received" "$LOG_FILE" 2>/dev/null || echo "0")
CSTORE_COUNT=$(grep -c -i "C-Store" "$LOG_FILE" 2>/dev/null || echo "0")

# Check if Weasis was likely the caller (Default Weasis AE title)
WEASIS_CALLER=$(grep -i "Calling AE Title" "$LOG_FILE" 2>/dev/null | grep -c -i "WEASIS" || echo "0")

# 3. Application State Check
APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# 4. Generate Results JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "total_files_received": $TOTAL_FILES,
    "new_files_received": $NEW_FILES,
    "association_count": $ASSOC_COUNT,
    "cstore_count": $CSTORE_COUNT,
    "weasis_aet_count": $WEASIS_CALLER,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="