#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Extension Installation Task Setup ==="
echo "Task: Install an ad-blocking extension from Chrome Web Store"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python packages for manifest parsing
pip3 install -q requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Determine Chrome profile path (try both possible locations)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -d "$CHROME_PROFILE" ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

# Create Extensions directory if it doesn't exist
EXTENSIONS_DIR="$CHROME_PROFILE/Extensions"
mkdir -p "$EXTENSIONS_DIR"
chown -R ga:ga "$CHROME_PROFILE" || true

echo "Using Chrome profile: $CHROME_PROFILE"
echo "Extensions directory: $EXTENSIONS_DIR"

# Record baseline extensions before task starts
echo "Recording baseline extensions..."
BASELINE_FILE="/tmp/baseline_extensions.txt"
if [ -d "$EXTENSIONS_DIR" ]; then
    ls -1 "$EXTENSIONS_DIR" 2>/dev/null | sort > "$BASELINE_FILE" || touch "$BASELINE_FILE"
    BASELINE_COUNT=$(wc -l < "$BASELINE_FILE" 2>/dev/null || echo "0")
    echo "✓ Baseline: $BASELINE_COUNT extension(s) currently installed"
else
    touch "$BASELINE_FILE"
    echo "✓ Baseline: No extensions directory yet (0 extensions)"
fi

# Also save detailed baseline with timestamps
if [ -d "$EXTENSIONS_DIR" ]; then
    find "$EXTENSIONS_DIR" -name "manifest.json" -type f > /tmp/baseline_manifests.txt 2>/dev/null || touch /tmp/baseline_manifests.txt
fi

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
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

# Navigate to Google homepage as neutral starting point
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is ready on Google homepage"
echo ""
echo "Agent should now:"
echo "  1. Navigate to Chrome Web Store (chrome.google.com/webstore)"
echo "  2. Search for 'ad blocker' or 'adblocker'"
echo "  3. Select a reputable ad-blocking extension (e.g., uBlock Origin, AdBlock)"
echo "  4. Click 'Add to Chrome'"
echo "  5. Accept permissions in the dialog"
echo "  6. Confirm installation completes successfully"