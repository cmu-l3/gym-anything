#!/usr/bin/env bash
set -euo pipefail

echo "=== Closing GIMP to save configuration ==="

# Function to send keystrokes as ga user
send_keys() {
    local keys="$1"
    su - ga -c "DISPLAY=:1 xdotool key $keys"
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

# Close GIMP using Ctrl+Q
echo "🚪 Closing GIMP to save configuration..."
send_keys "ctrl+q"
sleep 2

# Wait for GIMP to fully close
echo "⏳ Waiting for GIMP to close and save configuration..."
sleep 3

# Verify GIMP is closed
if pgrep -f "gimp" > /dev/null; then
    echo "⚠️ GIMP still running, trying to force close..."
    pkill -f gimp || true
    sleep 2
else
    echo "✅ GIMP closed successfully"
fi

# Check if gimprc was updated
if [ -f "/home/ga/.config/GIMP/2.10/gimprc" ]; then
    echo "📝 Configuration file exists:"
    ls -la "/home/ga/.config/GIMP/2.10/gimprc"
    echo "🔍 Checking for undo-levels setting:"
    grep -n "undo-levels" "/home/ga/.config/GIMP/2.10/gimprc" || echo "undo-levels not found in config"
else
    echo "⚠️ Configuration file not found at expected location"
fi

echo "=== GIMP configuration task completed ==="
