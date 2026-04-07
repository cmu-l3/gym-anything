#!/bin/bash
echo "=== Exporting un_style_voiceover_localization Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Tell Ardour to save the session via UI automation before closing
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    echo "Saving Ardour session..."
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    echo "Closing Ardour..."
    kill_ardour
fi

sleep 2

# Check the exported file
EXPORT_PATH="/home/ga/Audio/localized_export/un_style_mix.wav"
EXPORT_EXISTS="false"
EXPORT_CREATED_DURING_TASK="false"
EXPORT_SIZE=0

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
        EXPORT_CREATED_DURING_TASK="true"
    fi
fi

# Create a JSON payload with basic task metadata for the Python verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "export_exists": $EXPORT_EXISTS,
    "export_created_during_task": $EXPORT_CREATED_DURING_TASK,
    "export_size_bytes": $EXPORT_SIZE
}
EOF

# Safely move JSON to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="