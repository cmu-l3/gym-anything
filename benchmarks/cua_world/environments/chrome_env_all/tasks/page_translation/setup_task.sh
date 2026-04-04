#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Page Translation Task Setup: page_translation@1 ==="
echo "Task: Translate a Spanish language webpage to English"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python packages needed for verification (language detection)
pip3 install -q --no-warn-script-location langdetect 2>/dev/null || true

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

# Navigate to Spanish Wikipedia article on Artificial Intelligence
SPANISH_URL="https://es.wikipedia.org/wiki/Inteligencia_artificial"
echo "Navigating to Spanish page: $SPANISH_URL"

su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$SPANISH_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true

# Wait for page to fully load
echo "Waiting for Spanish Wikipedia page to load..."
sleep 5

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP and capture initial state
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Capture initial page state for verification baseline
    curl -s http://localhost:9222/json > /tmp/initial_tab_state.json 2>/dev/null || true
    
    # Extract and display initial title
    INITIAL_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/initial_tab_state.json 2>/dev/null || echo "Unknown")
    echo "✓ Initial page title: $INITIAL_TITLE"
    
    # Check if page is actually in Spanish
    if echo "$INITIAL_TITLE" | grep -qi "inteligencia"; then
        echo "✓ Confirmed: Page is in Spanish"
    else
        echo "⚠ Warning: Page title doesn't contain expected Spanish keywords"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome displaying Spanish Wikipedia article"
echo ""
echo "Agent should now:"
echo "  1. Wait for or trigger Chrome's translation prompt (infobar at top)"
echo "  2. Click 'Translate' button in the infobar"
echo "  3. Alternative: Right-click page → 'Translate to English'"
echo "  4. Alternative: Click translate icon in address bar (if visible)"
echo "  5. Confirm translation completes successfully"