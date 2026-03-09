#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Lighthouse Audit Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/lighthouse_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab URL via CDP
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Search for Lighthouse reports in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for Lighthouse reports in: $DOWNLOADS_DIR"

# Look for HTML reports first (most common format)
REPORT_FILE=""
REPORT_FORMAT=""

# Find most recent Lighthouse HTML report
if compgen -G "$DOWNLOADS_DIR/lighthouse*.html" > /dev/null 2>&1; then
    REPORT_FILE=$(ls -t "$DOWNLOADS_DIR"/lighthouse*.html 2>/dev/null | head -1)
    REPORT_FORMAT="html"
    echo "✓ Found Lighthouse HTML report: $(basename "$REPORT_FILE")"
elif compgen -G "$DOWNLOADS_DIR/*lighthouse*.html" > /dev/null 2>&1; then
    REPORT_FILE=$(ls -t "$DOWNLOADS_DIR"/*lighthouse*.html 2>/dev/null | head -1)
    REPORT_FORMAT="html"
    echo "✓ Found Lighthouse HTML report: $(basename "$REPORT_FILE")"
elif compgen -G "$DOWNLOADS_DIR/*report*.html" > /dev/null 2>&1; then
    # Check if it's a Lighthouse report by looking for lighthouse keyword in file
    for f in "$DOWNLOADS_DIR"/*report*.html; do
        if [ -f "$f" ] && grep -q "lighthouse" "$f" 2>/dev/null; then
            REPORT_FILE="$f"
            REPORT_FORMAT="html"
            echo "✓ Found Lighthouse HTML report: $(basename "$REPORT_FILE")"
            break
        fi
    done
fi

# If no HTML found, look for JSON reports
if [ -z "$REPORT_FILE" ]; then
    if compgen -G "$DOWNLOADS_DIR/lighthouse*.json" > /dev/null 2>&1; then
        REPORT_FILE=$(ls -t "$DOWNLOADS_DIR"/lighthouse*.json 2>/dev/null | head -1)
        REPORT_FORMAT="json"
        echo "✓ Found Lighthouse JSON report: $(basename "$REPORT_FILE")"
    elif compgen -G "$DOWNLOADS_DIR/*lighthouse*.json" > /dev/null 2>&1; then
        REPORT_FILE=$(ls -t "$DOWNLOADS_DIR"/*lighthouse*.json 2>/dev/null | head -1)
        REPORT_FORMAT="json"
        echo "✓ Found Lighthouse JSON report: $(basename "$REPORT_FILE")"
    fi
fi

# If still no report found, search by modification time (last 5 minutes)
if [ -z "$REPORT_FILE" ]; then
    echo "No report found by filename pattern, searching by modification time..."
    RECENT_HTML=$(find "$DOWNLOADS_DIR" -name "*.html" -type f -mmin -5 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    if [ -n "$RECENT_HTML" ] && [ -f "$RECENT_HTML" ]; then
        # Verify it's a Lighthouse report
        if grep -q "lighthouse\|lh-root\|lighthouse-version" "$RECENT_HTML" 2>/dev/null; then
            REPORT_FILE="$RECENT_HTML"
            REPORT_FORMAT="html"
            echo "✓ Found recent Lighthouse HTML report: $(basename "$REPORT_FILE")"
        fi
    fi
fi

# Copy report to verification directory if found
if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
    REPORT_NAME=$(basename "$REPORT_FILE")
    cp "$REPORT_FILE" "$VERIFY_DIR/"
    echo "$REPORT_NAME" > "$VERIFY_DIR/report_filename.txt"
    echo "$REPORT_FORMAT" > "$VERIFY_DIR/report_format.txt"
    
    # Get file size for debugging
    FILE_SIZE=$(stat -f%z "$REPORT_FILE" 2>/dev/null || stat -c%s "$REPORT_FILE" 2>/dev/null || echo "unknown")
    echo "Report file size: $FILE_SIZE bytes"
    echo "$FILE_SIZE" > "$VERIFY_DIR/report_size.txt"
    
    echo "✓ Report copied to verification directory"
else
    echo "⚠ No Lighthouse report found in Downloads folder"
    echo "none" > "$VERIFY_DIR/report_filename.txt"
    echo "unknown" > "$VERIFY_DIR/report_format.txt"
    
    # List Downloads contents for debugging
    echo "Contents of Downloads folder:"
    ls -lah "$DOWNLOADS_DIR" 2>/dev/null || echo "Could not list Downloads"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification directory contents to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $VERIFY_DIR"