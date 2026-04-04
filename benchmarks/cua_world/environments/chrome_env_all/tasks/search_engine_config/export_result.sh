#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Search Engine Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure any unsaved changes are committed
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_active_url.txt
    
    # Check if agent was on settings page
    if echo "$ACTIVE_URL" | grep -q "chrome://settings"; then
        echo "✓ Agent appears to have accessed Chrome settings"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/search_engine_final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/search_engine_final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save preferences to disk..."
# First try graceful shutdown
pkill -TERM -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences file..."

# Try multiple possible Chrome profile locations
PREFS_FOUND=false
PREFS_LOCATIONS=(
    "/home/ga/.config/google-chrome-cdp/Default/Preferences"
    "/home/ga/.config/google-chrome/Default/Preferences"
    "/home/ga/.config/chromium/Default/Preferences"
)

for PREFS_PATH in "${PREFS_LOCATIONS[@]}"; do
    if [ -f "$PREFS_PATH" ]; then
        echo "Found Preferences at: $PREFS_PATH"
        cp "$PREFS_PATH" /tmp/chrome_preferences_after_task.json
        
        # Verify file was copied and has content
        if [ -s /tmp/chrome_preferences_after_task.json ]; then
            echo "✓ Preferences exported to /tmp/chrome_preferences_after_task.json"
            FILE_SIZE=$(stat -f%z /tmp/chrome_preferences_after_task.json 2>/dev/null || stat -c%s /tmp/chrome_preferences_after_task.json 2>/dev/null || echo "unknown")
            echo "  File size: $FILE_SIZE bytes"
            
            # Extract and display search engine info for debugging
            if command -v jq &> /dev/null; then
                SEARCH_ENGINE=$(jq -r '.default_search_provider_data.short_name // "unknown"' /tmp/chrome_preferences_after_task.json 2>/dev/null || echo "unknown")
                SEARCH_KEYWORD=$(jq -r '.default_search_provider_data.keyword // "unknown"' /tmp/chrome_preferences_after_task.json 2>/dev/null || echo "unknown")
                echo "  Search engine: $SEARCH_ENGINE"
                echo "  Search keyword: $SEARCH_KEYWORD"
            fi
            
            PREFS_FOUND=true
            break
        fi
    fi
done

if [ "$PREFS_FOUND" = false ]; then
    echo "⚠ Warning: Could not find Preferences file in any known location"
    echo "Searched locations:"
    for loc in "${PREFS_LOCATIONS[@]}"; do
        echo "  - $loc"
    done
    
    # Create an empty marker file so verifier knows export failed
    echo '{"error": "Preferences file not found"}' > /tmp/chrome_preferences_after_task.json
fi

# Also copy to alternative names for robustness
cp /tmp/chrome_preferences_after_task.json /tmp/preferences_export.json 2>/dev/null || true

echo "✅ Export complete"
echo ""
echo "Files available for verification:"
echo "  - /tmp/chrome_preferences_after_task.json (main)"
echo "  - /tmp/preferences_export.json (alternative)"
echo "  - /tmp/final_active_url.txt (CDP active tab)"
echo "  - /tmp/search_engine_final_screenshot.png (visual debug)"