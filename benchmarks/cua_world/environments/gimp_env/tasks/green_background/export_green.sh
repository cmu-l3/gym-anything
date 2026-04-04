#!/usr/bin/env bash
set -euo pipefail

echo "=== Automating green background export process ==="

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
su - ga -c "DISPLAY=:1 xdotool mousemove --sync 800 600 click 1" || true
sleep 1

# Focus GIMP window first
echo "🎯 Focusing GIMP window..."
wid=$(wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}')
echo "GIMP window ID: $wid"
su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
sleep 1

# Export the green background image using Shift+Ctrl+E 
echo "📤 Triggering export dialog..."
send_keys "shift+ctrl+e"
sleep 2

# Type the export filename
echo "✏️ Setting export filename..."
send_text "green_background_with_object"
sleep 1

# Press Enter to confirm filename
send_keys "Return"
sleep 2

# Press Enter again to confirm export (in case of dialog)
send_keys "Return" 
sleep 3

# Verify the file was created
if [ -f "/home/ga/Desktop/green_background_with_object.png" ]; then
    echo "✅ Export successful: green_background_with_object.png created"
    chown ga:ga "/home/ga/Desktop/green_background_with_object.png"
    ls -la "/home/ga/Desktop/green_background_with_object.png"
else
    echo "⚠️ Export file not found, checking alternative locations..."
    find /home/ga -name "*green_background*" -type f 2>/dev/null || echo "No exported file found"
fi

echo "=== Green background export automation completed ==="
