#!/bin/bash
echo "=== Exporting Bilingual Legal Contract Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if application was running
APP_RUNNING="false"
if pgrep -f "DesktopEditors\|onlyoffice" > /dev/null; then
    APP_RUNNING="true"
    # Attempt to trigger save dialog and close (agent should have saved it properly, but we attempt a fallback save)
    DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
    su - ga -c "DISPLAY=:1 xdotool key ctrl+s" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
fi

# Kill to release file locks
pkill -f "DesktopEditors\|onlyoffice" 2>/dev/null || true

TARGET_FILE="/home/ga/Documents/TextDocuments/bilingual_nda_final.docx"
ALT_FILE="/home/ga/Documents/TextDocuments/bilingual_nda_draft.docx"

OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
FILE_PATH=""
EXACT_NAME="false"

# Prioritize the final expected name
if [ -f "$TARGET_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_PATH="$TARGET_FILE"
    EXACT_NAME="true"
    MTIME=$(stat -c %Y "$TARGET_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
elif [ -f "$ALT_FILE" ]; then
    # Fallback to the draft file if the agent saved over it instead of Save As
    MTIME=$(stat -c %Y "$ALT_FILE")
    if [ "$MTIME" -gt $((TASK_START + 5)) ]; then
        OUTPUT_EXISTS="true"
        FILE_PATH="$ALT_FILE"
        FILE_MODIFIED="true"
    fi
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_path": "$FILE_PATH",
    "exact_name": $EXACT_NAME,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

sudo cp "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="