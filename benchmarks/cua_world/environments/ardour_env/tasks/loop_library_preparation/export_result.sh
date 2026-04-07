#!/bin/bash
echo "=== Exporting loop_library_preparation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
sleep 1

# Gracefully save and close Ardour to ensure XML is written
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi
sleep 2

# Gather file system state
DELIVERY_DIR="/home/ga/Audio/loop_pack_delivery"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 1. Check for exported WAV files
WAV_COUNT=0
WAV_CREATED_DURING_TASK="false"
VALID_WAV_COUNT=0

if [ -d "$DELIVERY_DIR" ]; then
    WAV_FILES=$(find "$DELIVERY_DIR" -maxdepth 1 -name "*.wav" -type f 2>/dev/null)
    for f in $WAV_FILES; do
        WAV_COUNT=$((WAV_COUNT + 1))
        
        # Check size > 100 bytes to prevent empty files
        SIZE=$(stat -c %s "$f" 2>/dev/null || echo "0")
        if [ "$SIZE" -gt 100 ]; then
            VALID_WAV_COUNT=$((VALID_WAV_COUNT + 1))
        fi
        
        # Check timestamp
        MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$MTIME" -ge "$TASK_START" ]; then
            WAV_CREATED_DURING_TASK="true"
        fi
    done
fi

# 2. Check for metadata file
INFO_FILE="$DELIVERY_DIR/pack_info.txt"
INFO_EXISTS="false"
INFO_CREATED_DURING_TASK="false"

if [ -f "$INFO_FILE" ]; then
    INFO_EXISTS="true"
    MTIME=$(stat -c %Y "$INFO_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        INFO_CREATED_DURING_TASK="true"
    fi
fi

# Create result JSON securely
TEMP_JSON=$(mktemp /tmp/loop_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "wav_file_count": $WAV_COUNT,
    "valid_wav_count": $VALID_WAV_COUNT,
    "wav_created_during_task": $WAV_CREATED_DURING_TASK,
    "info_file_exists": $INFO_EXISTS,
    "info_created_during_task": $INFO_CREATED_DURING_TASK,
    "export_timestamp": $(date +%s)
}
EOF

rm -f /tmp/loop_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/loop_task_result.json
chmod 666 /tmp/loop_task_result.json
rm -f "$TEMP_JSON"

echo "Result data saved."
cat /tmp/loop_task_result.json
echo "=== Export Complete ==="