#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome QR Code Generation Task Setup ==="
echo "Task: Generate and download QR code for a webpage using Chrome's built-in feature"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install QR code verification dependencies
echo "Installing QR code processing libraries..."
pip3 install -q pillow pyzbar opencv-python-headless 2>/dev/null || {
    echo "⚠ Warning: Some Python libraries may not have installed properly"
}

# Install zbar library for QR decoding
# apt-get install -y -qq libzbar0 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to the target URL for QR code generation
TARGET_URL="https://example.com"
echo "Navigating to: $TARGET_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TARGET_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Wait for page to fully load
echo "Waiting for page to load..."
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Check active tab URL
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Clear Downloads folder to ensure clean verification
echo "Clearing Downloads folder..."
rm -f /home/ga/Downloads/*.png 2>/dev/null || true
rm -f /home/ga/Downloads/*qr*.* 2>/dev/null || true

echo "=== Setup complete ==="
echo "Chrome should be displaying: $TARGET_URL"
echo ""
echo "Agent should now:"
echo "  1. Right-click on the address bar (or click share button)"
echo "  2. Select 'Create QR Code for this page'"
echo "  3. Click 'Download' in the QR code dialog"
echo "  4. QR code PNG will be saved to Downloads folder"