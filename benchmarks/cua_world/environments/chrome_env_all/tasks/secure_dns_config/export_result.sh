#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Secure DNS Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# IMPORTANT: Gracefully close Chrome to ensure Preferences are persisted to disk
# Settings changes may not be written immediately, so we need to close Chrome properly
echo "Closing Chrome to save DNS configuration..."
pkill -TERM chrome 2>/dev/null || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 chrome 2>/dev/null || true
    sleep 1
fi

echo "Chrome closed successfully"

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for DNS verification..."

# Try multiple possible profile locations
PROFILE_LOCATIONS=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
    "/home/ga/.config/chromium/Default"
)

PREFS_FOUND=false
for CHROME_PROFILE in "${PROFILE_LOCATIONS[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "Found Preferences at: $CHROME_PROFILE/Preferences"
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_dns.json
        echo "✓ Preferences exported to /tmp/chrome_preferences_dns.json"
        
        # Also log the DNS configuration for debugging
        DNS_MODE=$(jq -r '.dns_over_https.mode // "not_configured"' /tmp/chrome_preferences_dns.json 2>/dev/null || echo "error")
        DNS_TEMPLATES=$(jq -r '.dns_over_https.templates // "not_configured"' /tmp/chrome_preferences_dns.json 2>/dev/null || echo "error")
        
        echo "DNS Configuration Found:"
        echo "  Mode: $DNS_MODE"
        echo "  Templates: $DNS_TEMPLATES"
        
        PREFS_FOUND=true
        break
    fi
done

if [ "$PREFS_FOUND" = false ]; then
    echo "⚠ Warning: Preferences file not found in any known location"
    echo "Searched locations:"
    for loc in "${PROFILE_LOCATIONS[@]}"; do
        echo "  - $loc/Preferences"
    done
    
    # Create empty file to prevent verification errors
    echo '{}' > /tmp/chrome_preferences_dns.json
fi

# Create a summary file with configuration info
cat > /tmp/dns_config_summary.txt << EOF
DNS Configuration Export Summary
================================
Timestamp: $(date)
Preferences Found: $PREFS_FOUND
Final URL: $ACTIVE_URL
EOF

if [ "$PREFS_FOUND" = true ]; then
    cat >> /tmp/dns_config_summary.txt << EOF
DNS Mode: $DNS_MODE
DNS Templates: $DNS_TEMPLATES
EOF
fi

echo "✅ Export complete"
echo "Files exported:"
echo "  - /tmp/chrome_preferences_dns.json (Preferences file)"
echo "  - /tmp/dns_config_summary.txt (Summary)"
echo "  - /tmp/final_screenshot.png (Screenshot)"