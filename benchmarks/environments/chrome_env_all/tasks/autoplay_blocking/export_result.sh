#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Media Autoplay Blocking Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Extract domain from URL for verification reference
    DOMAIN=$(echo "$ACTIVE_URL" | sed -E 's|https?://([^/]+).*|\1|' | sed 's/^www\.//')
    echo "Domain: $DOMAIN"
    echo "$DOMAIN" > /tmp/target_domain.txt
fi

# Take final screenshot before closing
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Final screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are persisted to disk
echo "Closing Chrome to save site-specific settings..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences file..."
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

PREFS_EXPORTED=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
        echo "✓ Saved to: /tmp/chrome_preferences.json"
        ls -lh "$CHROME_PROFILE/Preferences"
        PREFS_EXPORTED=true
        break
    fi
done

if [ "$PREFS_EXPORTED" = false ]; then
    echo "⚠ Warning: Preferences file not found in any known location"
    # List possible locations for debugging
    echo "Searched locations:"
    for profile in "${CHROME_PROFILES[@]}"; do
        echo "  - $profile/Preferences $([ -f "$profile/Preferences" ] && echo "[EXISTS]" || echo "[NOT FOUND]")"
    done
fi

# Create a verification metadata file
echo "Creating verification metadata..."
cat > /tmp/autoplay_task_metadata.json << EOF
{
  "task": "autoplay_blocking@1",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "target_url": "$(cat /tmp/final_url.txt 2>/dev/null || echo "unknown")",
  "target_domain": "$(cat /tmp/target_domain.txt 2>/dev/null || echo "unknown")",
  "preferences_exported": $PREFS_EXPORTED
}
EOF

echo "✅ Export complete"
echo "Verification files:"
echo "  - /tmp/chrome_preferences.json (Preferences file)"
echo "  - /tmp/autoplay_task_metadata.json (Task metadata)"
echo "  - /tmp/final_url.txt (Active URL)"
echo "  - /tmp/target_domain.txt (Target domain)"