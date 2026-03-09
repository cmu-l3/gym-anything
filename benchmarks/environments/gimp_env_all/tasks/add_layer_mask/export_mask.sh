#!/bin/bash
set -e

echo "=== Automating layer mask save process ==="

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
# Save as XCF using Ctrl+S (not export - we need native GIMP format)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 2

echo "✏️ Setting save filename..."
# Type the filename
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'mask_test_with_layer_mask'" || true
sleep 1

# Press Enter to save
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# Press Enter again if there's a confirmation dialog
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3

# Check if save was successful
if [ -f "/home/ga/Desktop/mask_test_with_layer_mask.xcf" ]; then
    echo "✅ Save successful: XCF file with layer mask created"
    ls -la /home/ga/Desktop/mask_test_with_layer_mask.xcf
    chown ga:ga /home/ga/Desktop/mask_test_with_layer_mask.xcf
else
    echo "⚠️ XCF file not found, checking alternative locations..."
    find /home/ga -name "*.xcf" -o -name "*mask*" 2>/dev/null | head -10
fi

echo "=== Layer mask save automation completed ==="