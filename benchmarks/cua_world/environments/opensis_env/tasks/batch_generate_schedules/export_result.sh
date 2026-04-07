#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOWNLOAD_DIR="/home/ga/Downloads"
TARGET_FILE=""
FILE_FOUND="false"
FILE_SIZE="0"
FILE_MTIME="0"

# 1. Find the most recently created PDF in Downloads
TARGET_FILE=$(find "$DOWNLOAD_DIR" -name "*.pdf" -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$TARGET_FILE" ] && [ -f "$TARGET_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Copy PDF to temp for extraction by verifier
    # We rename it to a known path so verifier can copy it easily
    cp "$TARGET_FILE" /tmp/generated_schedule.pdf
    chmod 666 /tmp/generated_schedule.pdf
fi

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_found": $FILE_FOUND,
    "original_path": "$TARGET_FILE",
    "file_size": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "pdf_staged_path": "/tmp/generated_schedule.pdf",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"