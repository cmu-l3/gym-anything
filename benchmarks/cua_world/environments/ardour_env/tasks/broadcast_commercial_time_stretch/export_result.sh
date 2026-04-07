#!/bin/bash
echo "=== Exporting broadcast_commercial_time_stretch result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Save and close if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
    kill_ardour
fi

sleep 1

# Extract lengths of all audio files in the session's audiofiles folder
# This is CRITICAL for the anti-gaming DSP check
FILE_INFO=$(python3 -c "
import os, json, wave
audio_dir = '/home/ga/Audio/sessions/MyProject/interchange/MyProject/audiofiles'
res = {}
if os.path.exists(audio_dir):
    for f in os.listdir(audio_dir):
        if f.lower().endswith('.wav'):
            path = os.path.join(audio_dir, f)
            try:
                with wave.open(path, 'r') as w:
                    res[f] = w.getnframes()
            except:
                res[f] = 0
print(json.dumps(res))
" 2>/dev/null || echo "{}")

# Extract length of the final exported WAV
EXPORT_FRAMES=$(python3 -c "
import wave
try:
    with wave.open('/home/ga/Audio/export/ad_voiceover_25s.wav', 'r') as w:
        print(w.getnframes())
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s),
    "audiofiles_info": $FILE_INFO,
    "exported_frames": $EXPORT_FRAMES
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="