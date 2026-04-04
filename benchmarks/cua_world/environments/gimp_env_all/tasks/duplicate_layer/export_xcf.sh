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

echo "💾 Saving as XCF to preserve layer structure..."
# Save as XCF using Ctrl+S (XCF is GIMP's native format that preserves layers)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 2

echo "✏️ Setting save filename..."
# Type the filename
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'duplicated_layers'" || true
sleep 1

# Press Enter to save
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3

# Also export as PNG for backup verification if needed
echo "📤 Creating backup PNG export..."
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+shift+e" || true
sleep 2

su - ga -c "DISPLAY=:1 xdotool type --delay 100 'layer_backup'" || true
sleep 1

su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3

# Check if save was successful
if [ -f "/home/ga/Desktop/duplicated_layers.xcf" ]; then
    echo "✅ Save successful: duplicated_layers.xcf created"
    ls -la /home/ga/Desktop/duplicated_layers.xcf
    chown ga:ga /home/ga/Desktop/duplicated_layers.xcf
else
    echo "⚠️ XCF file not found, checking alternative locations..."
    find /home/ga -name "*duplicated*" -o -name "*.xcf" 2>/dev/null | head -10
fi

echo "=== Layer duplication export automation completed ==="