#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Extension Management Task Setup: extension_disable_enable@1 ==="
echo "Task: Disable the Test Productivity Extension in chrome://extensions/"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 zip || true

# Wait for environment to be ready
sleep 2

# Create a simple test extension
echo "Creating test extension..."
EXTENSION_DIR="/tmp/test_extension"
mkdir -p "$EXTENSION_DIR"

# Create manifest.json for the test extension
cat > "$EXTENSION_DIR/manifest.json" << 'EOF'
{
  "manifest_version": 3,
  "name": "Test Productivity Extension",
  "version": "1.0.0",
  "description": "A simple test extension for Chrome extension management tasks",
  "icons": {
    "16": "icon.png",
    "48": "icon.png",
    "128": "icon.png"
  },
  "permissions": [
    "storage"
  ],
  "background": {
    "service_worker": "background.js"
  },
  "action": {
    "default_popup": "popup.html",
    "default_icon": "icon.png"
  }
}
EOF

# Create a simple background script
cat > "$EXTENSION_DIR/background.js" << 'EOF'
// Simple background script for test extension
chrome.runtime.onInstalled.addListener(() => {
  console.log('Test Productivity Extension installed');
});
EOF

# Create a simple popup HTML
cat > "$EXTENSION_DIR/popup.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <style>
    body { width: 200px; padding: 10px; font-family: Arial; }
    h3 { margin: 0 0 10px 0; color: #1a73e8; }
    p { margin: 5px 0; font-size: 12px; }
  </style>
</head>
<body>
  <h3>Test Extension</h3>
  <p>This is a test productivity extension.</p>
  <p>Status: Active</p>
</body>
</html>
EOF

# Create a simple icon (1x1 PNG - minimal valid PNG file)
# This is a base64-encoded 1x1 transparent PNG
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > "$EXTENSION_DIR/icon.png"

echo "✓ Test extension created at: $EXTENSION_DIR"

# Set ownership
chown -R ga:ga "$EXTENSION_DIR"

# Kill any existing Chrome processes to start fresh
echo "Stopping any existing Chrome processes..."
pkill -f "google-chrome" || true
pkill -f "chrome.*remote-debugging-port" || true
sleep 2

# Ensure Chrome profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome-cdp"

# Start Chrome with the test extension loaded
echo "Starting Chrome with test extension..."
su - ga -c "DISPLAY=:1 google-chrome-stable \
  --remote-debugging-port=1337 \
  --user-data-dir=/home/ga/.config/google-chrome-cdp \
  --no-first-run \
  --no-default-browser-check \
  --disable-popup-blocking \
  --disable-infobars \
  --load-extension=$EXTENSION_DIR \
  --new-window https://www.google.com \
  > /tmp/chrome_extension_task.log 2>&1 &"

# Wait for Chrome to start
sleep 5

# Wait for Chrome to be fully ready
echo "Waiting for Chrome to be ready..."
for i in {1..10}; do
  if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    break
  fi
  sleep 1
done

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
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

# Navigate to Google homepage as starting point
echo "Navigating to starting URL: https://www.google.com"
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

# Verify extension was loaded by checking Preferences
echo "Verifying extension was loaded..."
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    # Check if extension appears in Preferences
    EXTENSION_COUNT=$(jq -r '.extensions.settings | keys | length' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "0")
    echo "✓ Found $EXTENSION_COUNT extension(s) in Chrome profile"
    
    # Get extension ID and state
    if [ "$EXTENSION_COUNT" -gt 0 ]; then
        EXTENSION_ID=$(jq -r '.extensions.settings | keys[0]' "$CHROME_PROFILE/Preferences" 2>/dev/null)
        EXTENSION_STATE=$(jq -r ".extensions.settings.\"$EXTENSION_ID\".state" "$CHROME_PROFILE/Preferences" 2>/dev/null)
        echo "✓ Extension ID: $EXTENSION_ID"
        echo "✓ Extension initial state: $EXTENSION_STATE (1=enabled, 0=disabled)"
        
        # Save extension ID for verifier
        echo "$EXTENSION_ID" > /tmp/test_extension_id.txt
    fi
else
    echo "⚠ Warning: Preferences file not yet created"
fi

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    echo "✓ Chrome has $TAB_COUNT active tab(s)"
else
    echo "⚠ Warning: Chrome CDP not fully responding"
fi

echo "=== Setup complete ==="
echo "Chrome is ready with Test Productivity Extension installed and enabled"
echo ""
echo "Agent task:"
echo "  1. Navigate to chrome://extensions/ (type in address bar)"
echo "  2. Find 'Test Productivity Extension' in the list"
echo "  3. Click the toggle switch to DISABLE the extension"
echo "  4. Verify the toggle turns grey/off"
echo ""
echo "Extension should be disabled when task completes."