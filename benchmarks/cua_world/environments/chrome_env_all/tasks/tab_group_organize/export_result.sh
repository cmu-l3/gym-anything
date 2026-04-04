#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Group Organization Task Export: tab_group_organize@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture tab information via CDP before closing Chrome
echo "Capturing tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_with_groups.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_tabs_with_groups.json > /tmp/chrome_page_tabs_groups.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs_groups.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs and titles for debugging
    jq -r '.[] | "\(.url)|\(.title)"' /tmp/chrome_page_tabs_groups.json > /tmp/tab_list_groups.txt
    echo "Tab information saved"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "[]" > /tmp/chrome_page_tabs_groups.json
    touch /tmp/tab_list_groups.txt
fi

# Take a screenshot before closing
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/tab_groups_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/tab_groups_screenshot.png"
fi

# Wait a moment to ensure all user actions are complete
sleep 2

# Gracefully close Chrome to ensure tab group settings are persisted to disk
echo "Closing Chrome to save tab group configuration..."
pkill -f "google-chrome" || pkill -f "chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || pkill -9 -f "chrome" || true
    sleep 1
fi

# Export Chrome Preferences file which contains tab group metadata
echo "Exporting Chrome Preferences file..."

# Try primary location (chrome-cdp profile)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_groups.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    
    # Check if tab groups section exists
    if grep -q "tab_groups" /tmp/chrome_preferences_groups.json 2>/dev/null; then
        echo "✓ Tab groups section found in Preferences"
    else
        echo "⚠ Warning: No tab_groups section found in Preferences"
    fi
else
    echo "⚠ Primary profile not found, trying alternative location..."
    
    # Try alternative location (standard chrome profile)
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_groups.json
        echo "✓ Preferences exported from: $ALT_PROFILE/Preferences"
    else
        echo "✗ Could not find Preferences file in any known location"
        echo "{}" > /tmp/chrome_preferences_groups.json
    fi
fi

# Also check for Sessions file which might contain tab group state
for profile_path in "/home/ga/.config/google-chrome-cdp/Default" "/home/ga/.config/google-chrome/Default"; do
    if [ -d "$profile_path" ]; then
        echo "Checking for tab group data in: $profile_path"
        
        # Copy any tab group related files
        if [ -f "$profile_path/Preferences" ]; then
            cp "$profile_path/Preferences" "/tmp/prefs_backup_$(basename $(dirname $profile_path)).json" 2>/dev/null || true
        fi
        
        if [ -d "$profile_path/Local Storage" ]; then
            echo "  Found Local Storage directory"
        fi
    fi
done

# List what we captured
echo ""
echo "Exported files for verification:"
ls -lh /tmp/chrome_preferences_groups.json 2>/dev/null || echo "  ✗ Preferences file missing"
ls -lh /tmp/chrome_page_tabs_groups.json 2>/dev/null || echo "  ✗ CDP tabs file missing"
ls -lh /tmp/tab_groups_screenshot.png 2>/dev/null || echo "  ⚠ Screenshot missing"

echo "✅ Export complete"