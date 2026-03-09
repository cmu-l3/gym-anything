#!/bin/bash
set -e

echo "=== Automating flood fill export process ==="

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
# Now make the window full screen
su - ga -c "DISPLAY=:1 xdotool key --delay 200 F11" || true
sleep 1

echo "📤 Triggering export dialog..."
# Open export dialog using Ctrl+Shift+E
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+shift+e" || true
sleep 2

echo "✏️ Setting export filename..."
# Type the filename
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'flood_filled_shape'" || true
sleep 1

# Press Enter to export
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# Press Enter again to confirm export (in case of dialog)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3


# Check if export was successful
if [ -f "/home/ga/Desktop/flood_filled_shape.png" ]; then
    echo "✅ Export successful: flood_filled_shape image created"
    ls -la /home/ga/Desktop/flood_filled_shape.png
    chown ga:ga /home/ga/Desktop/flood_filled_shape.png
else
    echo "⚠️ Export file not found, checking alternative locations..."
    find /home/ga -name "*flood*" -o -name "*fill*" -o -name "*shape*" 2>/dev/null | head -10
fi

echo "=== Flood fill export automation completed ==="