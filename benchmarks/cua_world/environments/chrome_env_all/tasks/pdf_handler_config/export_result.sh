#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome PDF Handler Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/pdf_config_final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/pdf_config_final_screenshot.png"
fi

# Capture active tab URL via CDP for additional verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/pdf_config_final_url.txt
    
    # Check if agent is still in settings
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]] || [[ "$ACTIVE_URL" == *"settings"* ]]; then
        echo "✓ Agent appears to be in settings page"
    fi
fi

# Gracefully close Chrome to ensure preferences are persisted to disk
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."
EXPORTED=false

# Try primary location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_prefs_export.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    EXPORTED=true
    
    # Extract and display PDF setting for debugging
    PDF_SETTING=$(python3 -c "
import json
try:
    with open('/tmp/chrome_prefs_export.json', 'r') as f:
        prefs = json.load(f)
    val = prefs.get('plugins', {}).get('always_open_pdf_externally', False)
    print('TRUE (download)' if val else 'FALSE (open in Chrome)')
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null || echo "unknown")
    echo "✓ Final PDF handler setting: $PDF_SETTING"
fi

# Try alternative location if primary failed
if [ "$EXPORTED" = false ]; then
    echo "⚠ Primary location not found, trying alternative..."
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_prefs_export.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE/Preferences"
        EXPORTED=true
    fi
fi

if [ "$EXPORTED" = false ]; then
    echo "✗ Warning: Could not export Preferences file from any known location"
    echo "Checked locations:"
    echo "  - /home/ga/.config/google-chrome-cdp/Default/Preferences"
    echo "  - /home/ga/.config/google-chrome/Default/Preferences"
fi

# Create a summary file for verifier
cat > /tmp/pdf_config_summary.txt << EOF
PDF Handler Configuration Task Export Summary
=============================================
Timestamp: $(date)
Preferences Exported: $EXPORTED
Final Setting: ${PDF_SETTING:-unknown}
EOF

echo "✅ Export complete"
echo "Preferences file copied to: /tmp/chrome_prefs_export.json"