#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Zoom Configuration Task Setup ==="
echo "Task: Configure permanent zoom level for docs.python.org"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
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

# Clear any existing zoom settings for docs.python.org to ensure clean test
echo "Clearing any existing zoom settings for docs.python.org..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_CHROME_PROFILE="/home/ga/.config/google-chrome/Default"

# Function to remove zoom setting from Preferences file
remove_zoom_setting() {
    local prefs_file="$1"
    if [ -f "$prefs_file" ]; then
        echo "Found Preferences at: $prefs_file"
        # Backup original
        cp "$prefs_file" "${prefs_file}.backup_zoom" || true
        
        # Use Python to remove the zoom setting (safer than sed/awk for JSON)
        python3 << 'EOF' || true
import json
import sys

prefs_file = sys.argv[1] if len(sys.argv) > 1 else None
if not prefs_file:
    sys.exit(0)

try:
    with open(prefs_file, 'r', encoding='utf-8') as f:
        prefs = json.load(f)
    
    # Remove zoom settings for docs.python.org
    zoom_levels = prefs.get('profile', {}).get('per_host_zoom_levels', {})
    keys_to_remove = [k for k in zoom_levels.keys() if 'docs.python.org' in k]
    
    for key in keys_to_remove:
        del zoom_levels[key]
        print(f"Removed zoom setting for: {key}")
    
    # Save back
    with open(prefs_file, 'w', encoding='utf-8') as f:
        json.dump(prefs, f, indent=2)
    
    print("Zoom settings cleared successfully")
except Exception as e:
    print(f"Could not clear zoom settings: {e}")
    sys.exit(0)
EOF
python3 -c "
import json
import sys
prefs_file = '$prefs_file'
try:
    with open(prefs_file, 'r', encoding='utf-8') as f:
        prefs = json.load(f)
    zoom_levels = prefs.get('profile', {}).get('per_host_zoom_levels', {})
    keys_to_remove = [k for k in zoom_levels.keys() if 'docs.python.org' in k]
    for key in keys_to_remove:
        del zoom_levels[key]
    with open(prefs_file, 'w', encoding='utf-8') as f:
        json.dump(prefs, f, indent=2)
except: pass
" 2>/dev/null || true
    fi
}

# Try both possible Chrome profile locations
remove_zoom_setting "$CHROME_PROFILE/Preferences"
remove_zoom_setting "$ALT_CHROME_PROFILE/Preferences"

# Restart Chrome to load clean preferences
echo "Restarting Chrome to apply clean preferences..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 2

# Start Chrome again
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
sleep 5

# Focus Chrome window again
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -n "$wid" ]; then
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to docs.python.org
echo "Navigating to: https://docs.python.org/3/"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://docs.python.org/3/'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Final focus to ensure Chrome is active and page is loaded
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
echo "Chrome should be displaying: https://docs.python.org/3/"
echo "Agent should now:"
echo "  1. Press Ctrl++ (or Ctrl and Plus) multiple times to zoom in (or use Chrome menu)"
echo "  2. Increase zoom to approximately 125-150% for comfortable reading"
echo "  3. Chrome will automatically save this as a site-specific preference"
echo "  Alternative: Click three-dot menu → Use + button next to zoom percentage"