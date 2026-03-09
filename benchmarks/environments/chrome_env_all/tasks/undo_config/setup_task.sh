#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Extension Keyboard Shortcuts Configuration Task Setup ==="
echo "Task: Configure custom keyboard shortcut for Chrome extension"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 zip unzip || true

# Wait for environment to be ready
sleep 2

# Create a minimal test extension with keyboard shortcut support
echo "Creating test extension with keyboard shortcut support..."
EXTENSION_DIR="/tmp/test_extension"
mkdir -p "$EXTENSION_DIR"

# Create manifest.json for the test extension
cat > "$EXTENSION_DIR/manifest.json" << 'EOF'
{
  "manifest_version": 3,
  "name": "Quick Notes",
  "version": "1.0",
  "description": "A simple note-taking extension for testing keyboard shortcuts",
  "permissions": ["storage"],
  "action": {
    "default_popup": "popup.html",
    "default_icon": {
      "16": "icon.png",
      "48": "icon.png",
      "128": "icon.png"
    }
  },
  "commands": {
    "_execute_action": {
      "suggested_key": {
        "default": "Ctrl+Shift+U",
        "mac": "Command+Shift+U"
      },
      "description": "Open Quick Notes"
    },
    "toggle-feature": {
      "suggested_key": {
        "default": "Ctrl+Shift+N"
      },
      "description": "Toggle notes panel"
    }
  },
  "background": {
    "service_worker": "background.js"
  }
}
EOF

# Create a simple popup.html
cat > "$EXTENSION_DIR/popup.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <style>
    body { width: 300px; padding: 10px; font-family: Arial; }
    h3 { margin-top: 0; color: #333; }
  </style>
</head>
<body>
  <h3>Quick Notes</h3>
  <p>Test extension for keyboard shortcuts configuration.</p>
</body>
</html>
EOF

# Create background.js
cat > "$EXTENSION_DIR/background.js" << 'EOF'
chrome.commands.onCommand.addListener((command) => {
  console.log('Command triggered:', command);
});
EOF

# Create a simple icon (base64 encoded 16x16 PNG)
echo "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAAdgAAAHYBTnsmCAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAE4SURBVDiNpZMxSwNBEIVndu9yiYhYpBELCwsLsbAPaWxs/QH+AwsLCxsLC0G0srRIISKkSWFhJ1jYCBYWAUGwsBRBEBHBwsLGIs7sbjYmxvgKh525ee/bYe4YM2PMf4VpC3DOdwA4BHACYMkY8zXLAiLaIqIzIpomoq8qeX2Y0TkH5+AcEBGcc3DOw3sPH+K8g/Mekj5Ys+p8P6wAEW0T0QkR1aP3JtEPxWVJKFZSH0W1VrdmWcaIiLaIaF9RLQVxbxPGRHNE9JiMR/cxM7sgovV/ETnnEJi1KJZSvr/Vf6nzAcDyrAUA9gAsjhTQaDRQr9fhnIPWGlprSCmhtYaUEkIIKKWglIJSClJKaK2htR5ojwZQFEUxPj5eVhRFKaWEcy5p0lpDCIE+pZRZFMVDp9P5SH5vKopiqVKp7A8fY7NarcqsOzE0//7+AJmw4YuU9I0wAAAAAElFTkSuQmCC" | base64 -d > "$EXTENSION_DIR/icon.png" 2>/dev/null || {
  # Fallback: Create a minimal valid PNG if base64 decode fails
  python3 -c "import struct; f=open('$EXTENSION_DIR/icon.png','wb'); f.write(bytes([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,16,0,0,0,16,8,6,0,0,0,31,243,255,97,0,0,0,1,115,82,71,66,0,174,206,28,233,0,0,0,4,103,65,77,65,0,0,177,143,11,252,97,5,0,0,0,9,112,72,89,115,0,0,14,195,0,0,14,195,1,199,111,168,100,0,0,0,30,73,68,65,84,56,79,99,252,207,64,5,195,32,10,0,192,77,1,2,128,44,0,228,7,0,161,166,218,234,0,0,0,0,73,69,78,68,174,66,96,130])); f.close()"
}

chown -R ga:ga "$EXTENSION_DIR"
echo "✓ Test extension created at: $EXTENSION_DIR"

# Store extension ID for later reference (will be generated based on path hash)
# For unpacked extensions, the ID is deterministic based on the path
EXTENSION_ID_FILE="/tmp/extension_id.txt"

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
sleep 3

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

# Navigate to chrome://extensions to load the extension
echo "Navigating to chrome://extensions to load test extension..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://extensions'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Enable Developer Mode and load unpacked extension via keyboard
echo "Loading test extension..."
# Press Tab multiple times to reach Developer Mode toggle (typically 2-4 tabs)
for i in {1..3}; do
  su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Tab" || true
  sleep 0.3
done

# Press Space to toggle Developer Mode on
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers space" || true
sleep 1

# Press Tab to reach "Load unpacked" button
for i in {1..2}; do
  su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Tab" || true
  sleep 0.3
done

# Press Enter to click "Load unpacked"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Type the extension directory path in the file dialog
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 100 '/tmp/test_extension'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Try to extract extension ID from Chrome (best effort)
# The extension ID is visible on chrome://extensions page after loading
sleep 2
echo "Attempting to capture extension ID..."

# Take screenshot for debugging
su - ga -c "DISPLAY=:1 import -window root /tmp/extensions_page.png" 2>/dev/null || true

# For unpacked extensions loaded from /tmp/test_extension, the ID is deterministic
# We'll store a marker that the verifier can use to search for the extension
echo "Quick Notes" > "$EXTENSION_ID_FILE"
echo "✓ Extension loaded (ID will be determined during verification)"

# Navigate to starting URL (Google) to prepare for agent
echo "Navigating to starting URL..."
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
echo "Test extension 'Quick Notes' loaded with configurable keyboard shortcuts"
echo "Agent should now:"
echo "  1. Navigate to chrome://extensions/shortcuts"
echo "  2. Locate 'Quick Notes' extension"
echo "  3. Click on the shortcut input field for 'Open Quick Notes'"
echo "  4. Press Ctrl+Shift+E to assign the shortcut"
echo "  5. Verify the shortcut is displayed"