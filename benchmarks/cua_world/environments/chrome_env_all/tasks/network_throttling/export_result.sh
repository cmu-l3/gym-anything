#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Network Throttling Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq tesseract-ocr || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/network_throttling_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab URL via CDP
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/active_title.txt"
    
    # Count tabs (including devtools if open)
    TAB_COUNT=$(jq '[.[] | select(.type == "page")] | length' "$VERIFY_DIR/chrome_tabs.json")
    echo "Total tabs: $TAB_COUNT"
    echo "$TAB_COUNT" > "$VERIFY_DIR/tab_count.txt"
else
    echo "⚠ Warning: Could not capture CDP information"
    echo "" > "$VERIFY_DIR/active_url.txt"
    echo "1" > "$VERIFY_DIR/tab_count.txt"
fi

# Take screenshot of entire screen (shows Chrome with DevTools if open)
echo "Capturing screenshot for DevTools verification..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    if [ -f "$VERIFY_DIR/final_screenshot.png" ]; then
        echo "✓ Screenshot saved: $VERIFY_DIR/final_screenshot.png"
        ls -lh "$VERIFY_DIR/final_screenshot.png"
    else
        echo "⚠ Screenshot capture may have failed"
    fi
else
    echo "⚠ Warning: ImageMagick 'import' command not available for screenshots"
fi

# Try to capture just the Chrome window (more focused)
if command -v import &> /dev/null && [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 import -window $wid $VERIFY_DIR/chrome_window.png" 2>/dev/null || true
    if [ -f "$VERIFY_DIR/chrome_window.png" ]; then
        echo "✓ Chrome window screenshot saved"
    fi
fi

# Try OCR on screenshot to detect "Slow 3G" text
if command -v tesseract &> /dev/null && [ -f "$VERIFY_DIR/final_screenshot.png" ]; then
    echo "Running OCR to detect throttling setting..."
    tesseract "$VERIFY_DIR/final_screenshot.png" "$VERIFY_DIR/screenshot_text" 2>/dev/null || true
    if [ -f "$VERIFY_DIR/screenshot_text.txt" ]; then
        echo "✓ OCR completed"
        # Check for throttling-related keywords
        if grep -iq "slow.*3g\|3g.*slow\|network.*throttl" "$VERIFY_DIR/screenshot_text.txt"; then
            echo "✓ OCR detected throttling-related text"
        else
            echo "⚠ OCR did not detect clear throttling indicators"
        fi
    fi
fi

# Check window list for DevTools indicators
echo "Checking for DevTools window..."
wmctrl -l > "$VERIFY_DIR/window_list.txt" 2>/dev/null || true
if grep -iq "devtools\|developer tools" "$VERIFY_DIR/window_list.txt"; then
    echo "✓ DevTools window detected in window list"
    echo "true" > "$VERIFY_DIR/devtools_detected.txt"
else
    echo "⚠ DevTools window not clearly identified"
    echo "false" > "$VERIFY_DIR/devtools_detected.txt"
fi

# Export all verification data to standard temp location
echo "Copying verification files to /tmp/..."
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# Final summary
echo ""
echo "=== Verification Data Summary ==="
echo "Directory: $VERIFY_DIR"
ls -lh "$VERIFY_DIR" 2>/dev/null || echo "Could not list directory"

echo ""
echo "✅ Export complete"
echo "Verification files ready for analysis"