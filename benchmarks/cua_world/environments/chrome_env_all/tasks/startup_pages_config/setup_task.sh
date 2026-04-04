#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Startup Pages Configuration Task Setup ==="
echo "Task: Configure Chrome to open multiple pages on startup"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Reset Chrome startup preferences to default state
echo "Resetting Chrome startup preferences to default..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_CHROME_PROFILE="/home/ga/.config/google-chrome/Default"

# Function to reset startup settings in Preferences file
reset_startup_settings() {
    local prefs_file="$1"
    if [ -f "$prefs_file" ]; then
        echo "Resetting startup settings in: $prefs_file"
        # Backup original
        cp "$prefs_file" "${prefs_file}.backup_$(date +%s)" || true
        
        # Use Python to safely modify JSON
        python3 << EOF
import json
import sys

try:
    with open("$prefs_file", 'r') as f:
        prefs = json.load(f)
    
    # Reset startup behavior to default (New Tab page)
    if 'session' not in prefs:
        prefs['session'] = {}
    
    prefs['session']['restore_on_startup'] = 1  # 1 = Open New Tab page (default)
    prefs['session']['startup_urls'] = []  # Empty startup URLs
    
    with open("$prefs_file", 'w') as f:
        json.dump(prefs, f, indent=2)
    
    print("✓ Startup settings reset to default")
    sys.exit(0)
except Exception as e:
    print(f"⚠ Warning: Could not reset preferences: {e}")
    sys.exit(1)
EOF
    fi
}

# Try to reset preferences in both possible locations
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    reset_startup_settings "$CHROME_PROFILE/Preferences"
elif [ -f "$ALT_CHROME_PROFILE/Preferences" ]; then
    reset_startup_settings "$ALT_CHROME_PROFILE/Preferences"
else
    echo "No existing Preferences file found, will be created on first Chrome launch"
fi

# Ensure Chrome directories exist
mkdir -p "$CHROME_PROFILE" || true
mkdir -p "$ALT_CHROME_PROFILE" || true
chown -R ga:ga "/home/ga/.config/google-chrome-cdp" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config/google-chrome" 2>/dev/null || true

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running, kill it to apply preference reset
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome is running, restarting to apply default settings..."
    pkill -f "google-chrome" || true
    sleep 2
fi

# Start Chrome fresh
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
sleep 6

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
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Capture initial state for verification
echo "Capturing initial startup configuration..."
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    INITIAL_MODE=$(python3 -c "import json; prefs=json.load(open('$CHROME_PROFILE/Preferences')); print(prefs.get('session', {}).get('restore_on_startup', 1))" 2>/dev/null || echo "1")
    echo "Initial startup mode: $INITIAL_MODE (1=New Tab, 4=Specific pages, 5=Continue)"
elif [ -f "$ALT_CHROME_PROFILE/Preferences" ]; then
    INITIAL_MODE=$(python3 -c "import json; prefs=json.load(open('$ALT_CHROME_PROFILE/Preferences')); print(prefs.get('session', {}).get('restore_on_startup', 1))" 2>/dev/null || echo "1")
    echo "Initial startup mode: $INITIAL_MODE (1=New Tab, 4=Specific pages, 5=Continue)"
fi

echo ""
echo "=== Setup complete ==="
echo "Chrome is ready with default startup settings (New Tab page)."
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://settings (Ctrl+L, type 'chrome://settings', Enter)"
echo "  2. Scroll to 'On startup' section"
echo "  3. Select 'Open a specific page or set of pages' radio button"
echo "  4. Click 'Add a new page' button"
echo "  5. Enter URLs for productivity pages (e.g., Gmail, Calendar, project tools)"
echo "  6. Add 2-4 startup pages total"
echo "  7. Settings auto-save, no explicit save needed"
echo ""
echo "Example URLs to configure:"
echo "  - https://mail.google.com (Email)"
echo "  - https://calendar.google.com (Calendar)"
echo "  - https://trello.com or https://asana.com (Project management)"
echo "  - https://news.google.com (News)"