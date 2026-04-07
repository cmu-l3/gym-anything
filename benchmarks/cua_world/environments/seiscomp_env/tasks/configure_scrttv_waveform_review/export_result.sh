#!/bin/bash
echo "=== Exporting configure_scrttv_waveform_review results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot of the environment state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if scrttv process is running
SCRTTV_RUNNING="false"
if pgrep -f "scrttv" > /dev/null; then
    SCRTTV_RUNNING="true"
fi

# Parse scrttv.cfg content safely into JSON
SCRTTV_CFG_CONTENT=""
if [ -f "/home/ga/seiscomp/etc/scrttv.cfg" ]; then
    SCRTTV_CFG_CONTENT=$(cat /home/ga/seiscomp/etc/scrttv.cfg | jq -Rs .)
else
    SCRTTV_CFG_CONTENT="\"\""
fi

# Parse global.cfg content safely into JSON
GLOBAL_CFG_CONTENT=""
if [ -f "/home/ga/seiscomp/etc/global.cfg" ]; then
    GLOBAL_CFG_CONTENT=$(cat /home/ga/seiscomp/etc/global.cfg | jq -Rs .)
else
    GLOBAL_CFG_CONTENT="\"\""
fi

# Check expected screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_VALID="false"
SCREENSHOT_PATH="/home/ga/scrttv_screenshot.png"

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    # Check if created after task start and is a reasonable size for a screenshot (>10KB)
    if [ "$MTIME" -gt "$TASK_START" ] && [ "$SIZE" -gt 10240 ]; then
        SCREENSHOT_VALID="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scrttv_running": $SCRTTV_RUNNING,
    "scrttv_cfg": $SCRTTV_CFG_CONTENT,
    "global_cfg": $GLOBAL_CFG_CONTENT,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_valid": $SCREENSHOT_VALID
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="