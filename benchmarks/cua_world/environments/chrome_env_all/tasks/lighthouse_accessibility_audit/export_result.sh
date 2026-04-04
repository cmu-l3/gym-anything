#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Lighthouse Accessibility Audit Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/lighthouse_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab URL via CDP for verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
fi

# Look for Lighthouse report in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for Lighthouse report in Downloads folder..."

# Search for accessibility_audit_report files
REPORT_FOUND=false
REPORT_PATH=""
REPORT_NAME=""

# Try exact expected filename (JSON)
if [ -f "$DOWNLOADS_DIR/accessibility_audit_report.json" ]; then
    REPORT_FOUND=true
    REPORT_PATH="$DOWNLOADS_DIR/accessibility_audit_report.json"
    REPORT_NAME="accessibility_audit_report.json"
    echo "✓ Found expected JSON report: $REPORT_NAME"
# Try exact expected filename (HTML)
elif [ -f "$DOWNLOADS_DIR/accessibility_audit_report.html" ]; then
    REPORT_FOUND=true
    REPORT_PATH="$DOWNLOADS_DIR/accessibility_audit_report.html"
    REPORT_NAME="accessibility_audit_report.html"
    echo "✓ Found expected HTML report: $REPORT_NAME"
else
    # Search for any recent Lighthouse-like JSON files (created in last 5 minutes)
    echo "Exact filename not found, searching for recent Lighthouse reports..."
    
    # Try to find JSON files with lighthouse or accessibility in name
    RECENT_JSON=$(find "$DOWNLOADS_DIR" -type f \( -name "*lighthouse*.json" -o -name "*accessibility*.json" \) -mmin -5 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -n "$RECENT_JSON" ] && [ -f "$RECENT_JSON" ]; then
        REPORT_FOUND=true
        REPORT_PATH="$RECENT_JSON"
        REPORT_NAME=$(basename "$RECENT_JSON")
        echo "✓ Found recent Lighthouse JSON: $REPORT_NAME"
    else
        # Try HTML files
        RECENT_HTML=$(find "$DOWNLOADS_DIR" -type f \( -name "*lighthouse*.html" -o -name "*accessibility*.html" \) -mmin -5 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        
        if [ -n "$RECENT_HTML" ] && [ -f "$RECENT_HTML" ]; then
            REPORT_FOUND=true
            REPORT_PATH="$RECENT_HTML"
            REPORT_NAME=$(basename "$RECENT_HTML")
            echo "✓ Found recent Lighthouse HTML: $REPORT_NAME"
        fi
    fi
fi

if [ "$REPORT_FOUND" = true ]; then
    echo "Copying report for verification..."
    cp "$REPORT_PATH" "$VERIFY_DIR/"
    echo "$REPORT_NAME" > "$VERIFY_DIR/report_filename.txt"
    ls -lh "$REPORT_PATH"
else
    echo "⚠ No Lighthouse report found in Downloads folder"
    echo "none" > "$VERIFY_DIR/report_filename.txt"
    
    # List all files in Downloads for debugging
    echo "Contents of Downloads folder:"
    ls -lah "$DOWNLOADS_DIR" 2>/dev/null || true
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification info to /tmp for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"