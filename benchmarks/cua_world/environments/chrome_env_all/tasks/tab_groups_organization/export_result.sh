#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Groups Organization Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure state is current
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/tab_groups_verification"
mkdir -p "$VERIFY_DIR"

# Capture all tabs via CDP
echo "Capturing tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/all_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' "$VERIFY_DIR/all_tabs.json" > "$VERIFY_DIR/page_tabs.json"
    
    TAB_COUNT=$(jq 'length' "$VERIFY_DIR/page_tabs.json")
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs for easy verification
    jq -r '.[] | "\(.url)"' "$VERIFY_DIR/page_tabs.json" > "$VERIFY_DIR/tab_urls.txt"
    
    echo "Tab URLs:"
    cat "$VERIFY_DIR/tab_urls.txt"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "[]" > "$VERIFY_DIR/page_tabs.json"
    touch "$VERIFY_DIR/tab_urls.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy Chrome profile files that might contain tab group information
echo "Exporting Chrome profile data..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

# Try to copy Local State file (may contain tab group info)
if [ -f "/home/ga/.config/google-chrome-cdp/Local State" ]; then
    cp "/home/ga/.config/google-chrome-cdp/Local State" "$VERIFY_DIR/LocalState.json" 2>/dev/null || true
    echo "Local State file copied"
fi

# Try to copy Preferences (may contain tab group preferences)
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/Preferences.json" 2>/dev/null || true
    echo "Preferences file copied"
fi

# Try to copy Session files (may contain tab group session data)
if [ -d "$CHROME_PROFILE/Sessions" ]; then
    cp -r "$CHROME_PROFILE/Sessions" "$VERIFY_DIR/" 2>/dev/null || true
    echo "Session files copied"
fi

# Alternative: Try to capture tab group information via Chrome's internal page
echo "Attempting to query chrome://tab-groups-internals (if available)..."
# This is a best-effort attempt - may not work on all Chrome versions

# Copy all verification files to standard /tmp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# Create a marker file with tab count for quick verification
echo "$TAB_COUNT" > /tmp/final_tab_count.txt

echo "✅ Export complete"
echo "Verification files saved to: $VERIFY_DIR"