#!/bin/bash
set -e

echo "=== Automating rotation export process ==="

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
# Type the filename
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'rotated_landscape'" || true
sleep 1

# Press Enter to export
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# Press Enter again to confirm export (in case of dialog)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3

# Check if export was successful
if [ -f "/home/ga/Desktop/rotated_landscape.png" ] || [ -f "/home/ga/Desktop/rotated_landscape.jpg" ]; then
    echo "✅ Export successful: rotated_landscape image created"
    ls -la /home/ga/Desktop/rotated_landscape.*
    chown ga:ga /home/ga/Desktop/rotated_landscape.* 2>/dev/null || true
else
    echo "⚠️ Export file not found, checking alternative locations..."
    find /home/ga -name "*rotated*" -o -name "*landscape*" -name "*rotate*" 2>/dev/null | head -10
fi

echo "=== Rotation export automation completed ==="