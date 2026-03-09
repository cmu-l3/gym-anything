#!/bin/bash
# set -euo pipefail

echo "=== Exporting VLOOKUP Formula task result ==="

wid=$(wmctrl -l | grep -i 'calc' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    wmctrl -ia "$wid" || true
    sleep 1
fi

OUTPUT_FILE="/home/ga/Documents/vlookup_result.ods"

su - ga -c "DISPLAY=:1 xdotool key ctrl+shift+s" || true
sleep 2

su - ga -c "DISPLAY=:1 xdotool key ctrl+a" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --delay 50 '$OUTPUT_FILE'" || true
sleep 1

su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 2

su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 1

if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ VLOOKUP result exported"
else
    echo "⚠️ Export may have failed"
fi

echo "=== Export completed ==="
