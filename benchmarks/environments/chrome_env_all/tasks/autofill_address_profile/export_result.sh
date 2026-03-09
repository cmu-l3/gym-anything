#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome AutoFill Address Profile Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
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

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# CRITICAL: Close Chrome to ensure Web Data database is written and unlocked
echo "Closing Chrome to save AutoFill data..."
pkill -f "google-chrome" || pkill chrome || true
sleep 3

# Double-check Chrome is closed (Web Data is locked while Chrome is running)
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || pkill -9 chrome || true
    sleep 2
fi

# Verify Chrome is fully stopped
if pgrep -f chrome > /dev/null; then
    echo "⚠ Warning: Chrome processes still running"
    ps aux | grep chrome
else
    echo "✓ Chrome successfully stopped"
fi

# Export Web Data database to temporary location for verification
echo "Exporting Chrome Web Data database..."

# Try multiple possible Chrome profile locations
CHROME_PROFILE_LOCATIONS=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

WEB_DATA_FOUND=false

for CHROME_PROFILE in "${CHROME_PROFILE_LOCATIONS[@]}"; do
    if [ -f "$CHROME_PROFILE/Web Data" ]; then
        echo "✓ Found Web Data at: $CHROME_PROFILE/Web Data"
        
        # Copy Web Data database
        cp "$CHROME_PROFILE/Web Data" /tmp/web_data_export.db
        
        # Verify copy was successful
        if [ -f "/tmp/web_data_export.db" ] && [ -s "/tmp/web_data_export.db" ]; then
            echo "✓ Web Data exported to /tmp/web_data_export.db"
            ls -lh "/tmp/web_data_export.db"
            
            # Quick verification: check if database is readable
            if sqlite3 /tmp/web_data_export.db "SELECT COUNT(*) FROM autofill_profiles;" > /tmp/autofill_profile_count.txt 2>/dev/null; then
                PROFILE_COUNT=$(cat /tmp/autofill_profile_count.txt)
                echo "✓ Database readable: Found $PROFILE_COUNT autofill profile(s)"
            else
                echo "⚠ Warning: Database exists but may be corrupted"
            fi
            
            WEB_DATA_FOUND=true
            break
        else
            echo "⚠ Warning: Web Data copy failed or file is empty"
        fi
    fi
done

if [ "$WEB_DATA_FOUND" = false ]; then
    echo "✗ Error: Web Data database not found in any known location"
    echo "Searched locations:"
    for loc in "${CHROME_PROFILE_LOCATIONS[@]}"; do
        echo "  - $loc/Web Data"
    done
fi

# Export Preferences file as well (for debugging)
echo "Exporting Chrome Preferences..."
for CHROME_PROFILE in "${CHROME_PROFILE_LOCATIONS[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported to /tmp/chrome_preferences.json"
        break
    fi
done

# List all exported files for verification
echo "Exported files:"
ls -lh /tmp/web_data_export.db /tmp/autofill_task_start_time.txt /tmp/chrome_preferences.json 2>/dev/null || true

echo "✅ Export complete"