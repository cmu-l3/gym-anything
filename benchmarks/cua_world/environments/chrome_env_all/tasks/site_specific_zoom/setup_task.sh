#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Zoom Configuration Task Setup ==="
echo "Task: Configure different zoom levels for multiple websites"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Ensure jq is available for JSON manipulation
if ! command -v jq &> /dev/null; then
    echo "Installing jq for JSON processing..."
# apt-get install -y -qq jq || true
fi

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

# Clear any existing per-site zoom settings for clean slate
echo "Clearing existing per-site zoom settings..."
CHROME_PROFILE_PATHS=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

for CHROME_PROFILE in "${CHROME_PROFILE_PATHS[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "Found Preferences at: $CHROME_PROFILE/Preferences"
        
        # Backup current preferences
        cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup_$(date +%s)" || true
        
        # Use jq to remove per_host_zoom_levels if it exists
        if command -v jq &> /dev/null; then
            echo "Removing existing per-site zoom settings with jq..."
            jq 'del(.profile.per_host_zoom_levels)' "$CHROME_PROFILE/Preferences" > "$CHROME_PROFILE/Preferences.tmp" && \
            mv "$CHROME_PROFILE/Preferences.tmp" "$CHROME_PROFILE/Preferences" || true
            chown ga:ga "$CHROME_PROFILE/Preferences" || true
            echo "✓ Cleared per-site zoom settings"
        else
            echo "⚠ jq not available, skipping zoom settings cleanup"
        fi
        
        break  # Only process the first found profile
    fi
done

# Navigate to starting URL (Google as neutral starting point)
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Reset zoom to 100% for starting page
echo "Resetting zoom to 100% on starting page..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+0" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Get and display current tab info
    CURRENT_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '.[0].url // "unknown"')
    echo "✓ Current tab URL: $CURRENT_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is ready at starting position"
echo ""
echo "Agent should now:"
echo "  1. Navigate to http://example.com"
echo "  2. Set zoom to 150% (Ctrl+Plus 5 times, or Menu → Zoom)"
echo "  3. Navigate to http://info.cern.ch"
echo "  4. Set zoom to 75% (Ctrl+Minus 3 times, or Menu → Zoom)"
echo "  5. Navigate to http://textfiles.com"
echo "  6. Set zoom to 125% (Ctrl+Plus 2 times, or Menu → Zoom)"
echo ""
echo "Expected zoom levels:"
echo "  - example.com: 150% (1.5 multiplier)"
echo "  - info.cern.ch: 75% (0.75 multiplier)"
echo "  - textfiles.com: 125% (1.25 multiplier)"