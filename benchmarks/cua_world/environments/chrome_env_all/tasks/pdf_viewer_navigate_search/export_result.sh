#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome PDF Viewer Navigation and Search Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/pdf_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab information via CDP
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Extract active tab URL and title
    ACTIVE_TAB=$(jq '[.[] | select(.type == "page")][0]' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_URL=$(echo "$ACTIVE_TAB" | jq -r '.url // ""')
    ACTIVE_TITLE=$(echo "$ACTIVE_TAB" | jq -r '.title // ""')
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    
    # Save to individual files for easy access
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/active_title.txt"
    
    # Extract page number from URL fragment if present
    # Chrome PDF URLs can have fragments like: file:///path/file.pdf#page=7
    if echo "$ACTIVE_URL" | grep -q "#"; then
        URL_FRAGMENT=$(echo "$ACTIVE_URL" | sed 's/.*#//')
        echo "$URL_FRAGMENT" > "$VERIFY_DIR/url_fragment.txt"
        echo "URL Fragment: $URL_FRAGMENT"
        
        # Try to extract page number
        if echo "$URL_FRAGMENT" | grep -qE "page="; then
            PAGE_NUM=$(echo "$URL_FRAGMENT" | grep -oE "page=[0-9]+" | grep -oE "[0-9]+")
            echo "$PAGE_NUM" > "$VERIFY_DIR/page_number.txt"
            echo "Extracted Page Number: $PAGE_NUM"
        fi
    fi
    
    # Try to execute JavaScript to get PDF viewer state
    # Note: This may not work in all Chrome versions due to PDF viewer isolation
    ACTIVE_TAB_ID=$(echo "$ACTIVE_TAB" | jq -r '.id // ""')
    if [ -n "$ACTIVE_TAB_ID" ]; then
        echo "Attempting to query PDF viewer state via CDP..."
        # This would require CDP WebSocket connection, which is complex
        # For now, we rely on URL analysis and screenshots
    fi
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "" > "$VERIFY_DIR/active_url.txt"
    echo "" > "$VERIFY_DIR/active_title.txt"
fi

# Take screenshot for visual verification
echo "Taking screenshot..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to $VERIFY_DIR/final_screenshot.png"
    
    # Copy to /tmp for easier access
    cp "$VERIFY_DIR/final_screenshot.png" /tmp/final_screenshot.png 2>/dev/null || true
fi

# Copy PDF file for verification
echo "Copying PDF file for verification..."
if [ -f "/home/ga/Documents/research_methodology.pdf" ]; then
    cp "/home/ga/Documents/research_methodology.pdf" "$VERIFY_DIR/" || true
    echo "✓ PDF copied for verification"
fi

# Copy all verification files to /tmp for easier access by verifier
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# List all captured information
echo "=== Captured Information ==="
echo "Files in verification directory:"
ls -lh "$VERIFY_DIR" || true

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"