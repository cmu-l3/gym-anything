#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Clear Recent History Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a screenshot before closing Chrome
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Capture active tab URL via CDP for verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# IMPORTANT: Close Chrome gracefully to ensure History database is not locked
echo "Closing Chrome to access History database..."
pkill -f "google-chrome" || true
sleep 3

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Verify Chrome is fully closed
if pgrep -f "chrome" > /dev/null; then
    echo "⚠ Warning: Chrome processes still running"
    pkill -9 -f "chrome" || true
    sleep 1
fi

# Define Chrome profile paths
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

if [ -d "$CHROME_PROFILE" ]; then
    PROFILE_DIR="$CHROME_PROFILE"
elif [ -d "$ALT_PROFILE" ]; then
    PROFILE_DIR="$ALT_PROFILE"
else
    echo "⚠ Warning: Could not find Chrome profile directory"
    PROFILE_DIR="$CHROME_PROFILE"
fi

# Export History database for verification
HISTORY_DB="$PROFILE_DIR/History"
echo "Exporting History database from: $HISTORY_DB"

if [ -f "$HISTORY_DB" ]; then
    # Copy to verification directory
    mkdir -p /tmp/history_verification
    cp "$HISTORY_DB" /tmp/history_verification/History_after.db
    
    # Get entry count for logging
    AFTER_COUNT=$(sqlite3 "$HISTORY_DB" "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "unknown")
    echo "✓ History database copied"
    echo "✓ After-task entry count: $AFTER_COUNT"
    
    # Also copy to standard temp location
    cp "$HISTORY_DB" /tmp/History_after.db
else
    echo "✗ Warning: History database not found at $HISTORY_DB"
    
    # Try to find it in alternative locations
    if [ -f "$ALT_PROFILE/History" ]; then
        echo "Found History at alternative location: $ALT_PROFILE/History"
        mkdir -p /tmp/history_verification
        cp "$ALT_PROFILE/History" /tmp/history_verification/History_after.db
        cp "$ALT_PROFILE/History" /tmp/History_after.db
    fi
fi

# Export the before snapshot path for verifier
if [ -f "/tmp/history_verification/History_before.db" ]; then
    echo "✓ Before-task history snapshot available"
    BEFORE_COUNT=$(sqlite3 /tmp/history_verification/History_before.db "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "unknown")
    echo "✓ Before-task entry count: $BEFORE_COUNT"
else
    echo "⚠ Warning: Before-task history snapshot not found"
fi

# Create a summary file for the verifier
cat > /tmp/history_verification/summary.txt << EOF
History Verification Data
========================
Before DB: /tmp/history_verification/History_before.db
After DB: /tmp/history_verification/History_after.db
Before Count: $BEFORE_COUNT
After Count: $AFTER_COUNT
Timestamp: $(date)
EOF

echo "✅ Export complete"
echo "Verification data prepared in /tmp/history_verification/"