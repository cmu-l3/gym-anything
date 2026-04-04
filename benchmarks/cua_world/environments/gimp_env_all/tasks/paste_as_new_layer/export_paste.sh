#!/bin/bash
set -e

echo "=== Automating paste as new layer export process ==="

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

echo "📤 Exporting as XCF to preserve layer structure..."
# First export as XCF to preserve layers for verification
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 2

echo "✏️ Setting XCF filename..."
# Type the XCF filename
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'paste_layers_result'" || true
sleep 1

# Press Enter to save XCF
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# If dialog appears asking about XCF format, confirm
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

echo "📤 Also exporting flattened version..."
# Export flattened version using Ctrl+Shift+E
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+shift+e" || true
sleep 2

echo "✏️ Setting flattened export filename..."
# Type the flattened filename
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'paste_result_flattened'" || true
sleep 1

# Press Enter to export
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# Press Enter again to confirm export (in case of dialog)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3

# Check if exports were successful
echo "🔍 Checking export results..."
if [ -f "/home/ga/Desktop/paste_layers_result.xcf" ]; then
    echo "✅ XCF export successful: paste_layers_result.xcf created"
    ls -la /home/ga/Desktop/paste_layers_result.xcf
    chown ga:ga /home/ga/Desktop/paste_layers_result.xcf
fi

if [ -f "/home/ga/Desktop/paste_result_flattened.jpg" ] || [ -f "/home/ga/Desktop/paste_result_flattened.png" ]; then
    echo "✅ Flattened export successful"
    chown ga:ga /home/ga/Desktop/paste_result_flattened.* 2>/dev/null || true
    ls -la /home/ga/Desktop/paste_result_flattened.* 2>/dev/null || true
else
    echo "⚠️ Flattened export file not found, checking alternative locations..."
    find /home/ga -name "*paste*" -o -name "*layer*" 2>/dev/null | head -10
fi

echo "=== Paste as new layer export automation completed ==="