#!/bin/bash
echo "=== Exporting Magic Spell Sound Design Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Trigger a save in Ardour if it is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 2
    fi
    # Gracefully close Ardour to ensure all XML data is flushed
    kill_ardour
fi

sleep 1

# Check for the exported audio file
EXPORT_FILE="/home/ga/Audio/export/time_spell.wav"
EXPORT_EXISTS="false"
EXPORT_CREATED_DURING_TASK="false"
EXPORT_SIZE=0

if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_FILE" 2>/dev/null || echo "0")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$EXPORT_MTIME" -ge "$TASK_START" ]; then
        EXPORT_CREATED_DURING_TASK="true"
    fi
fi

# Create result JSON securely
TEMP_JSON=$(mktemp /tmp/magic_spell_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "export_file_exists": $EXPORT_EXISTS,
    "export_created_during_task": $EXPORT_CREATED_DURING_TASK,
    "export_file_size": $EXPORT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/magic_spell_result.json 2>/dev/null || sudo rm -f /tmp/magic_spell_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/magic_spell_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/magic_spell_result.json
chmod 666 /tmp/magic_spell_result.json 2>/dev/null || sudo chmod 666 /tmp/magic_spell_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/magic_spell_result.json"
cat /tmp/magic_spell_result.json

echo "=== Export Complete ==="