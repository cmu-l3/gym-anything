#!/bin/bash
set -e

echo "=== Automating horizontal shear export process ==="

# Install xdotool if not present
apt-get update -qq && apt-get install -y -qq xdotool wmctrl || true

# Function to send keystrokes as ga user
send_keys() {
    local keys="$1"
    su - ga -c "DISPLAY=:1 xdotool key $keys"
    sleep 0.5
}

send_text() {
    local text="$1" 
    su - ga -c "DISPLAY=:1 xdotool type '$text'"
    sleep 0.5
}

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
send_keys "ctrl+shift+e"
sleep 2

echo "✏️ Setting export filename..."
# Type the filename
send_text "sheared_image"
sleep 1

# Press Enter to export
send_keys "Return"
sleep 2

# Press Enter again to confirm export (in case of dialog)
send_keys "Return" 
sleep 3

# Check if export was successful
if [ -f "/home/ga/Desktop/sheared_image.jpg" ] || [ -f "/home/ga/Desktop/sheared_image.png" ]; then
    echo "✅ Export successful: sheared_image created"
    chown ga:ga /home/ga/Desktop/sheared_image.* 2>/dev/null || true
    ls -la /home/ga/Desktop/sheared_image.* 2>/dev/null || true
else
    echo "⚠️ Export file not found, checking alternative locations..."
    find /home/ga -name "*shear*" -o -name "*transformed*" 2>/dev/null | head -10
fi

echo "=== Horizontal shear export automation completed ==="