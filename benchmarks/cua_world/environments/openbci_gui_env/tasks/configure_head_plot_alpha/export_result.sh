#!/bin/bash
echo "=== Exporting Task Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# 1. Check Output Screenshot (Agent's Proof)
# ============================================================
EXPECTED_PATH="/home/ga/Documents/OpenBCI_GUI/Screenshots/alpha_topography.png"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$EXPECTED_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPECTED_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPECTED_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# ============================================================
# 2. Check Application State
# ============================================================
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# ============================================================
# 3. Capture Verification Screenshot (Ground Truth)
# ============================================================
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# ============================================================
# 4. Generate JSON Result
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $FILE_EXISTS,
    "output_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_file_size": $FILE_SIZE,
    "output_file_path": "$EXPECTED_PATH",
    "app_running": $APP_RUNNING,
    "verification_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="