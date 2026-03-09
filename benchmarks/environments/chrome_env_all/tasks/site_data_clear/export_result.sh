#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Complete Site Data Deletion Task Export: site_data_clear@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for debugging
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a screenshot before closing
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure data changes are persisted
echo "Closing Chrome to persist data changes..."
pkill -f "google-chrome" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

echo "Chrome stopped"

# Export Chrome data files for verification
echo "Exporting Chrome data files..."

# Determine Chrome profile path
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -d "$CHROME_PROFILE" ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

echo "Using Chrome profile: $CHROME_PROFILE"

# Create verification directory
VERIFY_DIR="/tmp/site_data_verification"
mkdir -p "$VERIFY_DIR"

# Copy Cookies database
if [ -f "$CHROME_PROFILE/Cookies" ]; then
    cp "$CHROME_PROFILE/Cookies" "$VERIFY_DIR/Cookies"
    echo "✓ Cookies database exported"
    
    # Quick check for target domain
    TARGET_DOMAIN="example.org"
    REMAINING_COOKIES=$(sqlite3 "$VERIFY_DIR/Cookies" "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%$TARGET_DOMAIN%';" 2>/dev/null || echo "error")
    echo "  Remaining cookies for $TARGET_DOMAIN: $REMAINING_COOKIES"
else
    echo "⚠ Warning: Cookies database not found"
fi

# Copy Preferences file
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/Preferences"
    echo "✓ Preferences file exported"
    
    # Quick check for target domain in preferences
    TARGET_DOMAIN="example.org"
    if grep -q "$TARGET_DOMAIN" "$VERIFY_DIR/Preferences"; then
        echo "  ⚠ $TARGET_DOMAIN still found in Preferences"
    else
        echo "  ✓ $TARGET_DOMAIN not found in Preferences"
    fi
else
    echo "⚠ Warning: Preferences file not found"
fi

# Copy Local Storage info if exists
if [ -d "$CHROME_PROFILE/Local Storage" ]; then
    # Just check if any files reference the domain
    ls -la "$CHROME_PROFILE/Local Storage/leveldb/" 2>/dev/null > "$VERIFY_DIR/local_storage_list.txt" || true
    echo "✓ Local Storage directory listing exported"
fi

# Export summary for quick reference
cat > "$VERIFY_DIR/export_summary.txt" <<EOF
Chrome Site Data Deletion Task Export Summary
=============================================
Export Time: $(date)
Target Domain: example.org
Chrome Profile: $CHROME_PROFILE

Files Exported:
- Cookies database
- Preferences file
- Local Storage listing

Verification will check:
1. No cookies remain for example.org
2. No permissions in Preferences for example.org
3. No custom settings (zoom levels) for example.org
4. No local storage data for example.org
EOF

echo ""
cat "$VERIFY_DIR/export_summary.txt"
echo ""

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"