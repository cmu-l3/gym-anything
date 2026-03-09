#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Anchor Navigation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary export directory
EXPORT_DIR="/tmp/anchor_navigation_export"
mkdir -p "$EXPORT_DIR"

# Capture active tab URL via CDP for verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > "$EXPORT_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$EXPORT_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$EXPORT_DIR/final_url.txt"
    
    # Extract fragment from URL if present
    if [[ "$ACTIVE_URL" == *"#"* ]]; then
        FRAGMENT="${ACTIVE_URL##*#}"
        echo "Current fragment: #$FRAGMENT"
        echo "$FRAGMENT" > "$EXPORT_DIR/final_fragment.txt"
    else
        echo "No fragment in current URL"
        echo "" > "$EXPORT_DIR/final_fragment.txt"
    fi
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $EXPORT_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Store timestamp for history verification
date +%s > "$EXPORT_DIR/task_end_timestamp.txt"

echo "Preparing to close Chrome to save History database..."
sleep 1

# Gracefully close Chrome to ensure History is persisted
echo "Closing Chrome to save history..."
pkill -SIGTERM chrome || true
sleep 3

# Force close if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force closing Chrome..."
    pkill -9 chrome || true
    sleep 1
fi

# Export History database
echo "Exporting Chrome History database..."
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

HISTORY_FOUND=false
for PROFILE_PATH in "${CHROME_PROFILES[@]}"; do
    HISTORY_DB="$PROFILE_PATH/History"
    if [ -f "$HISTORY_DB" ]; then
        echo "Found History at: $HISTORY_DB"
        cp "$HISTORY_DB" "$EXPORT_DIR/History"
        echo "✓ History database copied"
        
        # Try to extract recent URLs with fragments for quick verification
        if command -v sqlite3 &> /dev/null; then
            echo "Extracting recent fragment URLs..."
            sqlite3 "$EXPORT_DIR/History" \
                "SELECT url FROM urls WHERE url LIKE '%#%' ORDER BY last_visit_time DESC LIMIT 10;" \
                > "$EXPORT_DIR/fragment_urls.txt" 2>/dev/null || true
            
            if [ -s "$EXPORT_DIR/fragment_urls.txt" ]; then
                echo "Recent fragment URLs:"
                cat "$EXPORT_DIR/fragment_urls.txt"
            fi
        fi
        
        HISTORY_FOUND=true
        break
    fi
done

if [ "$HISTORY_FOUND" = false ]; then
    echo "⚠ Warning: History database not found in any profile location"
fi

# Copy all export files to standard /tmp location for verifier
cp -r "$EXPORT_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $EXPORT_DIR"