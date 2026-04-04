#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome History Recovery Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/history_recovery_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab URL via CDP
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Extract active tab URL and title
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/chrome_tabs.json")
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/active_title.txt"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "" > "$VERIFY_DIR/active_url.txt"
    echo "" > "$VERIFY_DIR/active_title.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Close Chrome gracefully to ensure history is saved to disk
echo "Closing Chrome to save history..."
pkill -f "google-chrome" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome History database for verification
echo "Exporting Chrome History database..."

# Try multiple possible Chrome profile locations
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

HISTORY_EXPORTED=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/History" ]; then
        echo "Found History database at: $CHROME_PROFILE/History"
        
        # Copy History database (it might be locked, so use sqlite3 backup)
        if sqlite3 "$CHROME_PROFILE/History" ".backup '$VERIFY_DIR/History'" 2>/dev/null; then
            echo "✓ History database backed up successfully"
            HISTORY_EXPORTED=true
            break
        else
            # Fallback: direct copy
            cp "$CHROME_PROFILE/History" "$VERIFY_DIR/History" 2>/dev/null && HISTORY_EXPORTED=true && break
        fi
    fi
done

if [ "$HISTORY_EXPORTED" = false ]; then
    echo "⚠ Warning: Could not export History database"
    # Create empty file to prevent verification errors
    touch "$VERIFY_DIR/History"
fi

# Copy verification files to standard /tmp location for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# Create a summary file
cat > /tmp/export_summary.txt << EOF
Chrome History Recovery Task Export Summary
===========================================
Active URL: $(cat "$VERIFY_DIR/active_url.txt" 2>/dev/null || echo "unknown")
Active Title: $(cat "$VERIFY_DIR/active_title.txt" 2>/dev/null || echo "unknown")
History Exported: $HISTORY_EXPORTED
Timestamp: $(date)
EOF

echo "✅ Export complete"
echo "Verification files copied to: $VERIFY_DIR and /tmp/"
cat /tmp/export_summary.txt