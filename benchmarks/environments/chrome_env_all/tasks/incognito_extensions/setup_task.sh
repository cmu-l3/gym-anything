#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Incognito Extensions Management Task Setup ==="
echo "Task: Enable extension for incognito mode and verify functionality"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 imagemagick || true

# Wait for environment to be ready
sleep 2

# Create a simple test extension with a known structure
echo "Creating test extension..."
TEST_EXT_DIR="/home/ga/test_extension"
mkdir -p "$TEST_EXT_DIR"

# Create manifest.json for the test extension
cat > "$TEST_EXT_DIR/manifest.json" << 'EOF'
{
  "manifest_version": 3,
  "name": "Incognito Test Extension",
  "version": "1.0.0",
  "description": "Simple test extension for incognito verification",
  "action": {
    "default_icon": {
      "16": "icon16.png",
      "48": "icon48.png"
    },
    "default_title": "Test Extension"
  },
  "permissions": [],
  "icons": {
    "16": "icon16.png",
    "48": "icon48.png"
  }
}
EOF

# Create simple icon files (1x1 red pixel PNG, base64 encoded)
# 16x16 red square
echo "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAFklEQVR42mP8z8DwHwyGBIwaMGoADQAAGgIB8i5XdWIAAAAASUVORK5CYII=" | base64 -d > "$TEST_EXT_DIR/icon16.png"
echo "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAASklEQVR42u3PMQ0AAAgDINc/tBk8QoKhsQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB4GwAA//8D4AAB9IyVeAAAAABJRU5ErkJggg==" | base64 -d > "$TEST_EXT_DIR/icon48.png"

# Set ownership
chown -R ga:ga "$TEST_EXT_DIR"
echo "✓ Test extension created at: $TEST_EXT_DIR"

# Ensure Chrome is running with proper settings
echo "Setting up Chrome for task..."

# Check if Chrome is running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome is running, will restart to load extension..."
    pkill -f "google-chrome" || true
    sleep 2
fi

# Launch Chrome with extension pre-loaded
echo "Launching Chrome with test extension..."
su - ga -c "DISPLAY=:1 google-chrome-stable \
    --remote-debugging-port=1337 \
    --no-first-run \
    --no-default-browser-check \
    --disable-popup-blocking \
    --disable-extensions-except=$TEST_EXT_DIR \
    --load-extension=$TEST_EXT_DIR \
    --user-data-dir=/home/ga/.config/google-chrome-cdp \
    'chrome://extensions' > /tmp/chrome_ga.log 2>&1 &"

sleep 6

# Wait for Chrome to be fully ready
echo "Waiting for Chrome to initialize..."
for i in {1..10}; do
    if curl -s http://localhost:9222/json > /dev/null 2>&1; then
        echo "✓ Chrome is ready"
        break
    fi
    echo "Waiting for Chrome... ($i/10)"
    sleep 1
done

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Chrome' | grep -i 'Extensions' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome Extensions window, trying general Chrome window"
    wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
fi

if [ -n "$wid" ]; then
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Find and store the extension ID
echo "Extracting extension ID..."
sleep 2

# Get extension ID from Chrome's Extensions directory
EXTENSIONS_DIR="/home/ga/.config/google-chrome-cdp/Default/Extensions"
if [ -d "$EXTENSIONS_DIR" ]; then
    # Find the directory that was most recently created (our extension)
    EXT_ID=$(ls -t "$EXTENSIONS_DIR" 2>/dev/null | head -1)
    if [ -n "$EXT_ID" ] && [ "$EXT_ID" != "Temp" ]; then
        echo "$EXT_ID" > /tmp/test_extension_id.txt
        echo "✓ Extension ID: $EXT_ID"
    else
        echo "⚠ Could not automatically detect extension ID, using fallback"
        # Try to extract from chrome://extensions page URL
        sleep 2
    fi
fi

# Alternative: Extract from Preferences file
PREFS_FILE="/home/ga/.config/google-chrome-cdp/Default/Preferences"
if [ -f "$PREFS_FILE" ]; then
    # Extract extension IDs from Preferences
    EXT_ID=$(jq -r '.extensions.settings | keys[] | select(length == 32)' "$PREFS_FILE" 2>/dev/null | grep -v "^$" | tail -1)
    if [ -n "$EXT_ID" ]; then
        echo "$EXT_ID" > /tmp/test_extension_id.txt
        echo "✓ Extension ID from Preferences: $EXT_ID"
    fi
fi

# Verify we have an extension ID
if [ ! -f /tmp/test_extension_id.txt ]; then
    # Create a placeholder - verifier will try to find it
    echo "unknown" > /tmp/test_extension_id.txt
    echo "⚠ Extension ID not found, verifier will attempt auto-detection"
fi

# Ensure we're on chrome://extensions page
echo "Navigating to chrome://extensions..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://extensions'" || true
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

# Take initial screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/initial_screenshot.png" 2>/dev/null || true
    echo "Initial screenshot saved"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying chrome://extensions with test extension loaded"
echo "Agent should:"
echo "  1. Locate the 'Incognito Test Extension' card"
echo "  2. Click 'Details' button"
echo "  3. Enable 'Allow in Incognito' toggle"
echo "  4. Press Ctrl+Shift+N to open incognito window"
echo "  5. Verify extension is available in incognito mode"