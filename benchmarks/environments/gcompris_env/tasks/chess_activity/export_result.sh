#!/bin/bash
set -e
echo "=== Exporting chess_activity result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Screenshot Evidence
SCREENSHOT_PATH="/home/ga/chess_progress.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"
SCREENSHOT_FRESH="false"
SCREENSHOT_SIZE="0"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    
    # Check size (>10KB implies not empty/black)
    SIZE=$(stat -c%s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SCREENSHOT_SIZE="$SIZE"
    if [ "$SIZE" -gt 10000 ]; then
        SCREENSHOT_VALID="true"
    fi
    
    # Check timestamp (must be created AFTER task start)
    MTIME=$(stat -c%Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_FRESH="true"
    fi
fi

# 2. Check Application State
APP_RUNNING="false"
if pgrep -f "gcompris" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Capture Final State for VLM
# (Even if agent took a screenshot, we take one to verify current state)
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
# Use temp file and move to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid": $SCREENSHOT_VALID,
    "screenshot_fresh": $SCREENSHOT_FRESH,
    "screenshot_size": $SCREENSHOT_SIZE,
    "app_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move to world-readable location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="