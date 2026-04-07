#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Save and close if Ardour is running to flush XML
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

sleep 1

# Gather Task Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"

# Check for exported WAV
EXPORT_DIR="/home/ga/Audio/radio_drama_mix"
FALLBACK_DIR="/home/ga/Audio/sessions/MyProject/export"
WAV_FOUND="false"
WAV_PATH=""
WAV_SIZE="0"
FILE_CREATED_DURING_TASK="false"

# Check primary dir
for f in "$EXPORT_DIR"/*.wav "$EXPORT_DIR"/*.WAV; do
    if [ -f "$f" ]; then
        WAV_FOUND="true"
        WAV_PATH="$f"
        WAV_SIZE=$(stat -c %s "$f" 2>/dev/null || echo "0")
        break
    fi
done

# Check fallback dir if not found
if [ "$WAV_FOUND" = "false" ]; then
    for f in "$FALLBACK_DIR"/*.wav "$FALLBACK_DIR"/*.WAV; do
        if [ -f "$f" ]; then
            WAV_FOUND="true"
            WAV_PATH="$f"
            WAV_SIZE=$(stat -c %s "$f" 2>/dev/null || echo "0")
            break
        fi
    done
fi

if [ "$WAV_FOUND" = "true" ] && [ -n "$WAV_PATH" ]; then
    WAV_MTIME=$(stat -c %Y "$WAV_PATH" 2>/dev/null || echo "0")
    if [ "$WAV_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Dump a basic JSON report
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "session_file_path": "$SESSION_FILE",
    "wav_found": $WAV_FOUND,
    "wav_path": "$WAV_PATH",
    "wav_size_bytes": $WAV_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="