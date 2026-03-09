#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Startup Pages Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture current active tab URL via CDP for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if agent was in settings
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent was in Chrome settings"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# CRITICAL: Close Chrome gracefully to ensure Preferences are saved to disk
echo "Closing Chrome to save startup preferences..."
pkill -TERM chrome 2>/dev/null || true
sleep 3

# Double-check Chrome is fully closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force closing..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

echo "✓ Chrome closed, preferences saved"

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences file..."

CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_CHROME_PROFILE="/home/ga/.config/google-chrome/Default"

# Try primary location first
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    ls -lh "$CHROME_PROFILE/Preferences"
    
    # Show startup configuration for debugging
    echo "Current startup configuration:"
    python3 << 'EOF'
import json
try:
    with open('/tmp/chrome_preferences.json', 'r') as f:
        prefs = json.load(f)
    session = prefs.get('session', {})
    restore_mode = session.get('restore_on_startup', 1)
    startup_urls = session.get('startup_urls', [])
    
    mode_names = {1: "New Tab page", 4: "Specific pages", 5: "Continue where left off"}
    print(f"  Mode: {restore_mode} ({mode_names.get(restore_mode, 'Unknown')})")
    print(f"  Startup URLs ({len(startup_urls)}):")
    for i, url in enumerate(startup_urls, 1):
        print(f"    {i}. {url}")
except Exception as e:
    print(f"  Could not parse: {e}")
EOF

elif [ -f "$ALT_CHROME_PROFILE/Preferences" ]; then
    cp "$ALT_CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported from alternative location: $ALT_CHROME_PROFILE/Preferences"
    ls -lh "$ALT_CHROME_PROFILE/Preferences"
    
    # Show startup configuration
    echo "Current startup configuration:"
    python3 << 'EOF'
import json
try:
    with open('/tmp/chrome_preferences.json', 'r') as f:
        prefs = json.load(f)
    session = prefs.get('session', {})
    restore_mode = session.get('restore_on_startup', 1)
    startup_urls = session.get('startup_urls', [])
    
    mode_names = {1: "New Tab page", 4: "Specific pages", 5: "Continue where left off"}
    print(f"  Mode: {restore_mode} ({mode_names.get(restore_mode, 'Unknown')})")
    print(f"  Startup URLs ({len(startup_urls)}):")
    for i, url in enumerate(startup_urls, 1):
        print(f"    {i}. {url}")
except Exception as e:
    print(f"  Could not parse: {e}")
EOF

else
    echo "⚠ Warning: Preferences file not found at either location"
    echo "  Tried: $CHROME_PROFILE/Preferences"
    echo "  Tried: $ALT_CHROME_PROFILE/Preferences"
    
    # Create an empty JSON to prevent verification errors
    echo '{"error": "preferences_not_found"}' > /tmp/chrome_preferences.json
fi

# Also copy to a secondary location as backup
cp /tmp/chrome_preferences.json /tmp/chrome_startup_prefs_backup.json 2>/dev/null || true

echo ""
echo "✅ Export complete"
echo "Preferences file ready for verification at /tmp/chrome_preferences.json"