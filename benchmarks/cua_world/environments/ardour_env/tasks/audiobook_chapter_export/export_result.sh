#!/bin/bash
echo "=== Exporting Audiobook Chapter Export Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Try to force a save if Ardour is running
if pgrep -f "/usr/lib/ardour" > /dev/null 2>&1; then
    echo "Ardour is running. Attempting to save session..."
    WID=$(DISPLAY=:1 xdotool search --name "MyProject" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
        sleep 3
    fi
fi

# Gather file statistics for exported WAVs
python3 -c "
import os
import json

exports = []
directories = ['/home/ga/Audio/audiobook_delivery', '/home/ga/Audio/sessions/MyProject/export']

for d in directories:
    if os.path.isdir(d):
        for f in os.listdir(d):
            if f.lower().endswith('.wav'):
                path = os.path.join(d, f)
                exports.append({
                    'filename': f,
                    'path': path,
                    'size_bytes': os.path.getsize(path),
                    'mtime': os.path.getmtime(path)
                })

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'exports': exports,
    'screenshot_path': '/tmp/task_final_state.png'
}

with open('/tmp/export_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/export_result.json 2>/dev/null || sudo chmod 666 /tmp/export_result.json 2>/dev/null || true
cp /tmp/export_result.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/export_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Task Result JSON generated:"
cat /tmp/task_result.json

echo "=== Export complete ==="