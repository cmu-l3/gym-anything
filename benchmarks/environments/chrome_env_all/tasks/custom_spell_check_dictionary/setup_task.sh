#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Custom Spell Check Dictionary Task Setup ==="
echo "Task: Add custom technical terms to Chrome's spell check dictionary"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

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

# Navigate to the starting URL (Google homepage)
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

# Backup existing custom dictionary if present (for clean testing)
echo "Backing up existing custom dictionary..."
DICT_FILE_CDP="/home/ga/.config/google-chrome-cdp/Default/Custom Dictionary.txt"
DICT_FILE_STD="/home/ga/.config/google-chrome/Default/Custom Dictionary.txt"

if [ -f "$DICT_FILE_CDP" ]; then
    cp "$DICT_FILE_CDP" "${DICT_FILE_CDP}.backup_$(date +%s)" 2>/dev/null || true
    echo "✓ Backed up custom dictionary from CDP profile"
fi

if [ -f "$DICT_FILE_STD" ]; then
    cp "$DICT_FILE_STD" "${DICT_FILE_STD}.backup_$(date +%s)" 2>/dev/null || true
    echo "✓ Backed up custom dictionary from standard profile"
fi

# Optionally clear the dictionary for a clean test (commented out to preserve user data)
# echo "" > "$DICT_FILE_CDP" 2>/dev/null || true
# echo "" > "$DICT_FILE_STD" 2>/dev/null || true

# Ensure Chrome spell check is enabled (via Preferences if needed)
echo "Ensuring spell check is enabled..."
for PROFILE_DIR in "/home/ga/.config/google-chrome-cdp/Default" "/home/ga/.config/google-chrome/Default"; do
    if [ -f "$PROFILE_DIR/Preferences" ]; then
        # Backup preferences
        cp "$PROFILE_DIR/Preferences" "$PROFILE_DIR/Preferences.backup" 2>/dev/null || true
        
        # Note: Directly editing JSON is risky; better to let Chrome update it
        # We'll just ensure the file exists so Chrome can write to it
        echo "✓ Chrome Preferences found at $PROFILE_DIR"
    fi
done

echo "=== Setup complete ==="
echo "Chrome is ready at: https://www.google.com"
echo ""
echo "Agent should now:"
echo "  1. Open Chrome Settings (chrome://settings or via menu)"
echo "  2. Navigate to: Languages section"
echo "  3. Find 'Spell check' section"
echo "  4. Click 'Custom spelling dictionary' or 'Custom dictionary'"
echo "  5. Add the following words (one at a time):"
echo "     - TensorFlow (capital T, capital F)"
echo "     - Kubernetes (capital K)"
echo "     - PostgreSQL (capital P, S, Q, L)"
echo "     - Dockerfile (capital D)"
echo "  6. Ensure correct capitalization for each word"
echo ""
echo "Expected result: All 4 words saved to Custom Dictionary.txt"