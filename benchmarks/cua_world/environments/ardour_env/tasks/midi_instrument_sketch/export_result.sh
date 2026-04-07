#!/bin/bash
echo "=== Exporting MIDI Instrument Sketch task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end_state.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_state.png 2>/dev/null || true

# Save Ardour session cleanly
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    pkill -f "/usr/lib/ardour" 2>/dev/null || true
    sleep 2
fi

SESSION_FILE="/home/ga/Audio/sessions/MyProject/MyProject.ardour"
SESSION_EXISTS="false"
if [ -f "$SESSION_FILE" ]; then
    SESSION_EXISTS="true"
fi

# Check for output WAV
OUTPUT_PATH="/home/ga/Audio/midi_render/tension_motif.wav"
WAV_EXISTS="false"
WAV_SIZE_BYTES=0
WAV_MTIME=0

if [ -f "$OUTPUT_PATH" ]; then
    WAV_EXISTS="true"
    WAV_SIZE_BYTES=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    WAV_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    # Fallback check in default export directory
    ALT_PATH=$(find /home/ga/Audio/sessions/MyProject/export -name "*.wav" -type f -newermt "@$TASK_START" 2>/dev/null | head -1)
    if [ -n "$ALT_PATH" ] && [ -f "$ALT_PATH" ]; then
        WAV_EXISTS="true"
        WAV_SIZE_BYTES=$(stat -c %s "$ALT_PATH" 2>/dev/null || echo "0")
        WAV_MTIME=$(stat -c %Y "$ALT_PATH" 2>/dev/null || echo "0")
        OUTPUT_PATH="$ALT_PATH"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/midi_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "session_exists": $SESSION_EXISTS,
    "wav_exists": $WAV_EXISTS,
    "wav_size_bytes": $WAV_SIZE_BYTES,
    "wav_mtime": $WAV_MTIME,
    "wav_path": "$OUTPUT_PATH",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/midi_instrument_sketch_result.json 2>/dev/null || sudo rm -f /tmp/midi_instrument_sketch_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/midi_instrument_sketch_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/midi_instrument_sketch_result.json
chmod 666 /tmp/midi_instrument_sketch_result.json 2>/dev/null || sudo chmod 666 /tmp/midi_instrument_sketch_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/midi_instrument_sketch_result.json"
cat /tmp/midi_instrument_sketch_result.json
echo "=== Export Complete ==="