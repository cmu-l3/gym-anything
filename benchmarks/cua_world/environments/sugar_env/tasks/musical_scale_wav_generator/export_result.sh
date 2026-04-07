#!/bin/bash
echo "=== Exporting musical_scale_wav_generator task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/musical_scale_end.png" 2>/dev/null || true

WAV_FILE="/home/ga/Documents/c_major_scale.wav"
TXT_FILE="/home/ga/Documents/note_frequencies.txt"
TASK_START=$(cat /tmp/musical_scale_start_ts 2>/dev/null || echo "0")

WAV_EXISTS="false"
WAV_SIZE=0
WAV_MODIFIED="false"

TXT_EXISTS="false"
TXT_SIZE=0
TXT_MODIFIED="false"

if [ -f "$WAV_FILE" ]; then
    WAV_EXISTS="true"
    WAV_SIZE=$(stat --format=%s "$WAV_FILE" 2>/dev/null || echo "0")
    WAV_MTIME=$(stat --format=%Y "$WAV_FILE" 2>/dev/null || echo "0")
    if [ "$WAV_MTIME" -gt "$TASK_START" ]; then
        WAV_MODIFIED="true"
    fi
fi

if [ -f "$TXT_FILE" ]; then
    TXT_EXISTS="true"
    TXT_SIZE=$(stat --format=%s "$TXT_FILE" 2>/dev/null || echo "0")
    TXT_MTIME=$(stat --format=%Y "$TXT_FILE" 2>/dev/null || echo "0")
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_MODIFIED="true"
    fi
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "wav_exists": $WAV_EXISTS,
    "wav_size": $WAV_SIZE,
    "wav_modified": $WAV_MODIFIED,
    "txt_exists": $TXT_EXISTS,
    "txt_size": $TXT_SIZE,
    "txt_modified": $TXT_MODIFIED,
    "task_start": $TASK_START
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="