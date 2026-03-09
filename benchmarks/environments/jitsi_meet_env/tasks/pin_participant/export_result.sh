#!/bin/bash
echo "=== Exporting Pin Participant result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if applications are still running
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")
EPIPHANY_RUNNING=$(pgrep -f "epiphany" > /dev/null && echo "true" || echo "false")

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "firefox_running": $FIREFOX_RUNNING,
    "epiphany_running": $EPIPHANY_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"