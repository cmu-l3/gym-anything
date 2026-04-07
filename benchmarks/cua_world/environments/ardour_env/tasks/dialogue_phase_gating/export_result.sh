#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Dialogue Phase Gating Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
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

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPORT_PATH="/home/ga/Audio/interview_fixed/dialogue_mix.wav"

EXPORT_EXISTS="false"
EXPORT_MTIME="0"
EXPORT_SIZE="0"
EXPORT_RMS_DB="-120.0"

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    # Calculate RMS amplitude of exported audio using sox
    # This proves whether the phase cancellation was fixed.
    # If not fixed, RMS will be near -inf. If fixed, it will be normal speech level.
    if command -v sox &>/dev/null; then
        RMS_AMP=$(sox "$EXPORT_PATH" -n stat 2>&1 | grep "RMS     amplitude" | awk '{print $3}')
        if [ -n "$RMS_AMP" ]; then
            EXPORT_RMS_DB=$(python3 -c "import math; print(round(20 * math.log10(float('$RMS_AMP') + 1e-10), 2))" 2>/dev/null || echo "-120.0")
        fi
    fi
fi

# Determine if file was created during task
FILE_CREATED_DURING_TASK="false"
if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/dialogue_phase_gating_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "session_file_exists": $([ -f "$SESSION_FILE" ] && echo "true" || echo "false"),
    "export_exists": $EXPORT_EXISTS,
    "export_mtime": $EXPORT_MTIME,
    "export_size_bytes": $EXPORT_SIZE,
    "export_rms_db": $EXPORT_RMS_DB,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location accessible by verifier
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="