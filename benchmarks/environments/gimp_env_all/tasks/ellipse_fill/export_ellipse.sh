#!/bin/bash
set -e

echo "=== Automating ellipse fill export process ==="

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
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'red_circle'" || true
sleep 1

# Press Enter to export
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# Press Enter again to confirm export (in case of dialog)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3


# Check if export was successful
if [ -f "/home/ga/Desktop/red_circle.png" ]; then
    echo "✅ Export successful: red_circle.png created"
    ls -la /home/ga/Desktop/red_circle.png
    chown ga:ga /home/ga/Desktop/red_circle.png
elif [ -f "/home/ga/Desktop/red_circle.jpg" ]; then
    echo "✅ Export successful: red_circle.jpg created"
    ls -la /home/ga/Desktop/red_circle.jpg
    chown ga:ga /home/ga/Desktop/red_circle.jpg
else
    echo "⚠️ Export file not found, checking alternative locations..."
    find /home/ga -name "*red_circle*" -o -name "*circle*" -o -name "*ellipse*" 2>/dev/null | head -10
fi

echo "=== Ellipse fill export automation completed ==="