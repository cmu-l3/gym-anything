#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Battery Saver Mode Configuration Task Setup ==="
echo "Task: Disable hardware acceleration to extend battery life"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

echo "Setting up Chrome for battery saver configuration task..."

# Ensure Chrome is NOT running so we can set initial state
echo "Stopping any existing Chrome instances..."
pkill -f "chrome" || true
sleep 2

# Ensure hardware acceleration is ENABLED by default in preferences
# This gives the agent something to actually change
CHROME_PROFILE_DIR="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE_DIR"

# Backup existing preferences if they exist
if [ -f "$CHROME_PROFILE_DIR/Preferences" ]; then
    cp "$CHROME_PROFILE_DIR/Preferences" "$CHROME_PROFILE_DIR/Preferences.backup_$(date +%s)" || true
    echo "✓ Backed up existing Preferences"
fi

# Ensure hardware acceleration is explicitly enabled in Preferences
# (Chrome default is enabled, but we make it explicit for clarity)
if [ -f "$CHROME_PROFILE_DIR/Preferences" ]; then
    echo "Ensuring hardware acceleration is enabled in existing Preferences..."
    python3 -c "
import json
import sys
try:
    with open('$CHROME_PROFILE_DIR/Preferences', 'r') as f:
        prefs = json.load(f)
    
    # Ensure hardware_acceleration_mode exists and is enabled
    if 'hardware_acceleration_mode' not in prefs:
        prefs['hardware_acceleration_mode'] = {}
    prefs['hardware_acceleration_mode']['enabled'] = True
    
    with open('$CHROME_PROFILE_DIR/Preferences', 'w') as f:
        json.dump(prefs, f, indent=2)
    
    print('✓ Hardware acceleration explicitly enabled in Preferences')
except Exception as e:
    print(f'⚠ Could not modify Preferences: {e}', file=sys.stderr)
    sys.exit(0)  # Don't fail setup, Chrome will create defaults
" || echo "⚠ Could not pre-configure Preferences (will use Chrome defaults)"
else
    echo "No existing Preferences file, Chrome will create with defaults (hardware acceleration enabled)"
fi

# Set ownership
chown -R ga:ga "$CHROME_PROFILE_DIR" || true

# Now launch Chrome with hardware acceleration enabled (default behavior)
echo "Launching Chrome with hardware acceleration enabled..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh chrome://settings/system" &
sleep 5

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

# Ensure we're on the System settings page
echo "Navigating to chrome://settings/system..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://settings/system'" || true
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
echo "Chrome should be displaying: chrome://settings/system"
echo "Hardware acceleration is currently ENABLED (default state)"
echo ""
echo "Agent task:"
echo "  1. Locate 'Use hardware acceleration when available' toggle"
echo "  2. Click the toggle to DISABLE hardware acceleration"
echo "  3. Click 'Relaunch' button if prompted (or Chrome will save on close)"
echo ""
echo "Optional bonus:"
echo "  - Navigate to Settings > Performance"
echo "  - Enable 'Memory Saver' if available"
echo "  - Enable 'Energy Saver' if available"