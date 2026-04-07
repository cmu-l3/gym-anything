#!/bin/bash
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps for anti-gaming checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SLVS_FILE="/home/ga/Documents/SolveSpace/18650_holder.slvs"
STL_FILE="/home/ga/Documents/SolveSpace/18650_holder.stl"

# Evaluate .slvs state
SLVS_EXISTS="false"
SLVS_MTIME="0"
SLVS_SIZE="0"
if [ -f "$SLVS_FILE" ]; then
    SLVS_EXISTS="true"
    SLVS_MTIME=$(stat -c %Y "$SLVS_FILE")
    SLVS_SIZE=$(stat -c %s "$SLVS_FILE")
fi

# Evaluate .stl state
STL_EXISTS="false"
STL_MTIME="0"
STL_SIZE="0"
if [ -f "$STL_FILE" ]; then
    STL_EXISTS="true"
    STL_MTIME=$(stat -c %Y "$STL_FILE")
    STL_SIZE=$(stat -c %s "$STL_FILE")
fi

APP_RUNNING=$(pgrep -f "solvespace" > /dev/null && echo "true" || echo "false")

# Safely construct JSON report via temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_mtime": $SLVS_MTIME,
    "slvs_size": $SLVS_SIZE,
    "stl_exists": $STL_EXISTS,
    "stl_mtime": $STL_MTIME,
    "stl_size": $STL_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move payload to standardized location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="