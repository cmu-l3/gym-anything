#!/bin/bash
set -e

echo "=== Automating merge down export process ==="

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

echo "💾 Saving XCF file first..."
# Save the XCF file to preserve layer structure (Ctrl+S)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 2

# If save dialog appears, confirm the filename
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 1

echo "📸 Creating flattened export for verification..."
# Export flattened version using Ctrl+Shift+E
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+shift+e" || true
sleep 2

echo "✏️ Setting export filename..."
# Type the filename for flattened export
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'merged_result'" || true
sleep 1

# Press Enter to export
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# Press Enter again to confirm export (in case of dialog)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3

# Check if files were created successfully
echo "🔍 Checking exported files..."

if [ -f "/home/ga/Desktop/multi_layer_composition.xcf" ]; then
    echo "✅ XCF file saved successfully"
    ls -la /home/ga/Desktop/multi_layer_composition.xcf
    chown ga:ga /home/ga/Desktop/multi_layer_composition.xcf
else
    echo "⚠️ XCF file may not have been saved properly"
fi

if [ -f "/home/ga/Desktop/merged_result.png" ] || [ -f "/home/ga/Desktop/merged_result.jpg" ]; then
    echo "✅ Flattened export successful"
    ls -la /home/ga/Desktop/merged_result.* 2>/dev/null || true
    chown ga:ga /home/ga/Desktop/merged_result.* 2>/dev/null || true
else
    echo "⚠️ Flattened export not found, checking alternative locations..."
    find /home/ga -name "*merged*" -o -name "*result*" 2>/dev/null | head -5
fi

echo "=== Merge down export automation completed ==="