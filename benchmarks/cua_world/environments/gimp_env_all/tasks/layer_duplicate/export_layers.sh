#!/bin/bash
set -e

echo "=== Automating layer duplication export process ==="

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

echo "📤 Triggering XCF export dialog..."
# Save as XCF to preserve layer information using Ctrl+S
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 2

echo "✏️ Setting export filename..."
# Clear any existing filename and type the new one
su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+a" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'duplicated_layers'" || true
sleep 1

# Press Enter to save
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# Press Enter again if there's a confirmation dialog
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3

# Check if export was successful
if [ -f "/home/ga/Desktop/duplicated_layers.xcf" ]; then
    echo "✅ Export successful: duplicated_layers.xcf created"
    ls -la /home/ga/Desktop/duplicated_layers.xcf
    chown ga:ga /home/ga/Desktop/duplicated_layers.xcf
else
    echo "⚠️ Export file not found, checking alternative locations..."
    find /home/ga -name "*duplicated*" -o -name "*layer*" 2>/dev/null | head -10
fi

echo "=== Layer duplication export automation completed ==="