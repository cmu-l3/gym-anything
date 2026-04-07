#!/bin/bash
echo "=== Exporting Documentary Narration Edit Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_final_state.png
else
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true
fi

# Save and close if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    if type kill_ardour &>/dev/null; then
        kill_ardour
    else
        pkill -f "/usr/lib/ardour" 2>/dev/null || true
    fi
fi

sleep 2

# Count exported WAV files
EXPORT_COUNT=0
EXPORT_DIR="/home/ga/Audio/documentary_export"
if [ -d "$EXPORT_DIR" ]; then
    EXPORT_COUNT=$(find "$EXPORT_DIR" -maxdepth 1 -name "*.wav" -type f 2>/dev/null | wc -l)
fi

# Fallback checking default export dir
DEFAULT_EXPORT_DIR="/home/ga/Audio/sessions/MyProject/export"
DEFAULT_EXPORT_COUNT=0
if [ -d "$DEFAULT_EXPORT_DIR" ]; then
    DEFAULT_EXPORT_COUNT=$(find "$DEFAULT_EXPORT_DIR" -maxdepth 1 -name "*.wav" -type f 2>/dev/null | wc -l)
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_REGIONS=$(cat /tmp/initial_region_count.txt 2>/dev/null || echo "0")

# Create results JSON
TEMP_JSON=$(mktemp /tmp/doc_narration_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_region_count": $INITIAL_REGIONS,
    "export_count": $EXPORT_COUNT,
    "default_export_count": $DEFAULT_EXPORT_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move JSON to final location safely
rm -f /tmp/doc_narration_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/doc_narration_result.json
chmod 666 /tmp/doc_narration_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/doc_narration_result.json"
echo "=== Export Complete ==="