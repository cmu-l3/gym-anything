#!/bin/bash
set -e

echo "=== Automating blend mode export process ==="

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

# First, save the XCF file to preserve layer information
echo "💾 Saving XCF file with layer data..."
# Save XCF using Ctrl+S
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" || true
sleep 2
# Type filename for XCF
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'blended_multiply'" || true
sleep 1
# Press Enter to save XCF
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# Now export PNG for visual verification
echo "📤 Triggering PNG export dialog..."
# Open export dialog using Ctrl+Shift+E
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+shift+e" || true
sleep 2

echo "✏️ Setting PNG export filename..."
# Type the filename for PNG export
su - ga -c "DISPLAY=:1 xdotool type --delay 100 'blended_multiply'" || true
sleep 1

# Press Enter to export PNG
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 2

# Press Enter again to confirm export (in case of dialog)
su - ga -c "DISPLAY=:1 xdotool key --delay 200 Return" || true
sleep 3

# Check if exports were successful
if [ -f "/home/ga/Desktop/blended_multiply.xcf" ] || [ -f "/home/ga/Desktop/blended_multiply.png" ]; then
    echo "✅ Export successful:"
    ls -la /home/ga/Desktop/blended_multiply.* 2>/dev/null || true
    chown ga:ga /home/ga/Desktop/blended_multiply.* 2>/dev/null || true
else
    echo "⚠️ Export files not found, checking alternative locations..."
    find /home/ga -name "*blend*" -o -name "*multiply*" 2>/dev/null | head -10
fi

echo "=== Blend mode export automation completed ==="