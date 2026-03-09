#!/bin/bash
echo "=== Exporting Bain Task Results ==="

# Source utilities
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    function take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check JASP Project File
JASP_FILE="/home/ga/Documents/JASP/Viagra_Bain.jasp"
JASP_EXISTS="false"
JASP_SIZE="0"
JASP_CREATED_DURING="false"

if [ -f "$JASP_FILE" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c%s "$JASP_FILE" 2>/dev/null || echo "0")
    JASP_MTIME=$(stat -c%Y "$JASP_FILE" 2>/dev/null || echo "0")
    
    if [ "$JASP_MTIME" -gt "$TASK_START" ]; then
        JASP_CREATED_DURING="true"
    fi
    
    # Copy for verification
    cp "$JASP_FILE" /tmp/Viagra_Bain.jasp 2>/dev/null || true
    chmod 666 /tmp/Viagra_Bain.jasp 2>/dev/null || true
fi

# 4. Check Text Result File
TEXT_FILE="/home/ga/Documents/JASP/bain_results.txt"
TEXT_EXISTS="false"
TEXT_CONTENT=""
TEXT_CREATED_DURING="false"

if [ -f "$TEXT_FILE" ]; then
    TEXT_EXISTS="true"
    TEXT_MTIME=$(stat -c%Y "$TEXT_FILE" 2>/dev/null || echo "0")
    if [ "$TEXT_MTIME" -gt "$TASK_START" ]; then
        TEXT_CREATED_DURING="true"
    fi
    TEXT_CONTENT=$(cat "$TEXT_FILE" | head -n 1) # Read first line
    
    # Copy for verification (redundant but safe)
    cp "$TEXT_FILE" /tmp/bain_results.txt 2>/dev/null || true
    chmod 666 /tmp/bain_results.txt 2>/dev/null || true
fi

# 5. Check if App is running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "jasp_file_exists": $JASP_EXISTS,
    "jasp_file_size": $JASP_SIZE,
    "jasp_created_during_task": $JASP_CREATED_DURING,
    "text_file_exists": $TEXT_EXISTS,
    "text_content": "$TEXT_CONTENT",
    "text_created_during_task": $TEXT_CREATED_DURING,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json