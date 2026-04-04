#!/bin/bash
set -e

echo "=== Automating object erase export process ==="

# Install xdotool if not present
apt-get update -qq && apt-get install -y -qq xdotool wmctrl || true

# Click on center of the screen (so if workspaces are open, we can focus on the first one)
# su - ga -c "DISPLAY=:1 xdotool mousemove --sync 800 600 click 1" || true
sleep 1

# Focus GIMP window first
echo "🎯 Focusing GIMP window..."
wid=$(wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}')
echo "GIMP window ID: $wid"
su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
sleep 1

echo "📤 Triggering export dialog..."
# Open export dialog using Ctrl+Shift+E
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+shift+e" || true
sleep 2

echo "✏️ Setting export filename..."
# Clear any existing filename and type the new one
su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+a" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'object_removed.png'" || true
sleep 1

# Press Enter to export
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# Press Enter again to confirm export (in case of dialog)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3

# Check if export was successful
if [ -f "/home/ga/Desktop/object_removed.png" ]; then
    echo "✅ Export successful: object_removed.png created"
    ls -la /home/ga/Desktop/object_removed.png
    chown ga:ga /home/ga/Desktop/object_removed.png
else
    echo "⚠️ Export file not found, checking alternative locations..."
    find /home/ga -name "*object_removed*" -o -name "*erased*" -o -name "*removed*" 2>/dev/null | head -10
fi

echo "=== Object erase export automation completed ==="