#!/usr/bin/env bash
set -euo pipefail

echo "=== Automating export process ==="

# Ensure xdotool is available
if ! command -v xdotool &> /dev/null; then
    echo "Installing xdotool..."
    apt-get update && apt-get install -y xdotool
fi

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

# Focus GIMP window first

# Click on center of the screen
su - ga -c "DISPLAY=:1 xdotool mousemove --sync 800 600 click 1" || true
sleep 1

echo "🎯 Focusing GIMP window..."
wid=$(wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}')
echo "GIMP window ID: $wid"
su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
sleep 1

# Export the edited image using Shift+Ctrl+E
echo "📤 Triggering export dialog..."
send_keys "shift+ctrl+e"
sleep 2

# Type the export filename
echo "✏️ Setting export filename..."
send_text "edited_darker"
sleep 1

# Press Enter to confirm filename
send_keys "Return"
sleep 3

# Press Enter again to confirm export (in case of dialog)
send_keys "Return" 
sleep 5

# Verify the file was created
if [ -f "/home/ga/Desktop/edited_darker.png" ]; then
    echo "✅ Export successful: edited_darker.png created"
    chown ga:ga "/home/ga/Desktop/edited_darker.png"
    ls -la "/home/ga/Desktop/edited_darker.png"
else
    echo "⚠️ Export file not found, trying alternative export location..."
    # Sometimes GIMP saves in different locations, let's check
    find /home/ga -name "*edited_darker*" -type f 2>/dev/null || echo "No exported file found"
fi

echo "=== Export automation completed ==="
