#!/bin/bash
set -e

echo "=== OSWorld: Close GIMP to persist settings ==="
# Focus GIMP window and quit to save preferences
su - ga -c "DISPLAY=:1 xdotool mousemove --sync 800 600 click 1" || true
wid=$(wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}')
[ -n "$wid" ] && su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
su - ga -c "DISPLAY=:1 xdotool key ctrl+q" || true
sleep 1
# Confirm dialogs if any
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 1
echo "✅ GIMP closed. Preferences should be saved."
