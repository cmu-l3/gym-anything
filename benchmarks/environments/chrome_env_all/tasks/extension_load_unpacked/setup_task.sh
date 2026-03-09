#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Extension Load Unpacked Task Setup ==="
echo "Task: Load unpacked Chrome extension in developer mode"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create test extension directory with all required files
echo "Creating test extension at /home/ga/test_extension/..."
EXTENSION_DIR="/home/ga/test_extension"
mkdir -p "$EXTENSION_DIR"

# Create manifest.json (Manifest V3 format)
cat > "$EXTENSION_DIR/manifest.json" << 'EOF'
{
  "manifest_version": 3,
  "name": "Test Extension",
  "version": "1.0.0",
  "description": "A test extension for agent training - demonstrates basic Chrome extension structure",
  "icons": {
    "16": "icon.png",
    "48": "icon.png",
    "128": "icon.png"
  },
  "background": {
    "service_worker": "background.js"
  },
  "permissions": [],
  "host_permissions": []
}
EOF

# Create simple background service worker
cat > "$EXTENSION_DIR/background.js" << 'EOF'
// Simple background service worker for Test Extension
console.log('Test Extension background service worker loaded successfully');

// Log installation
chrome.runtime.onInstalled.addListener((details) => {
  console.log('Test Extension installed:', details.reason);
  if (details.reason === 'install') {
    console.log('This is a fresh installation of Test Extension');
  }
});

// Keep service worker alive with periodic tasks
self.addEventListener('activate', (event) => {
  console.log('Test Extension service worker activated');
});
EOF

# Create a minimal valid PNG icon (1x1 transparent pixel)
# This is a base64-encoded 1x1 transparent PNG
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d > "$EXTENSION_DIR/icon.png"

# Set proper ownership and permissions
chown -R ga:ga "$EXTENSION_DIR"
chmod -R 755 "$EXTENSION_DIR"

echo "✓ Test extension created with following structure:"
ls -lah "$EXTENSION_DIR"

# Verify extension files
echo "✓ Verifying extension files..."
if [ -f "$EXTENSION_DIR/manifest.json" ]; then
    echo "  - manifest.json: OK"
    cat "$EXTENSION_DIR/manifest.json" | head -5
else
    echo "  - manifest.json: MISSING!"
fi

if [ -f "$EXTENSION_DIR/background.js" ]; then
    echo "  - background.js: OK"
else
    echo "  - background.js: MISSING!"
fi

if [ -f "$EXTENSION_DIR/icon.png" ]; then
    echo "  - icon.png: OK ($(stat -c%s "$EXTENSION_DIR/icon.png") bytes)"
else
    echo "  - icon.png: MISSING!"
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

# Navigate to the starting URL (Google as neutral starting point)
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
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "unknown")
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Test extension ready at: $EXTENSION_DIR"
echo "Chrome is focused and ready at: https://www.google.com"
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://extensions"
echo "  2. Enable 'Developer mode' toggle (top right)"
echo "  3. Click 'Load unpacked' button"
echo "  4. Select directory: /home/ga/test_extension/"
echo "  5. Confirm selection"