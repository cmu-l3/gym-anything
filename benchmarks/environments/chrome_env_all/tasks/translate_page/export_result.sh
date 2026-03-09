#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Page Translation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/translate_verification"
mkdir -p "$VERIFY_DIR"

echo "Capturing final page state..."

# Capture active tab info via CDP
if curl -s http://localhost:9222/json > "$VERIFY_DIR/final_tabs.json" 2>/dev/null; then
    ACTIVE_TAB=$(jq -r '[.[] | select(.type == "page")][0]' "$VERIFY_DIR/final_tabs.json")
    ACTIVE_URL=$(echo "$ACTIVE_TAB" | jq -r '.url // ""')
    ACTIVE_TITLE=$(echo "$ACTIVE_TAB" | jq -r '.title // ""')
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
    
    echo "$ACTIVE_TAB" > "$VERIFY_DIR/final_active_tab.json"
fi

# Extract page content using JavaScript via xdotool (fallback method)
# This is a simplified approach - in production, we'd use CDP WebSocket
echo "Extracting final page content..."

# Method 1: Try to use Chrome's "Save Page As" to get final HTML
# This is complex with xdotool, so we'll use a Python script via CDP

python3 << 'PYTHON_EOF'
import json
import urllib.request
import sys

try:
    # Get active tab
    response = urllib.request.urlopen('http://localhost:9222/json')
    tabs = json.loads(response.read().decode())
    
    page_tabs = [t for t in tabs if t.get('type') == 'page']
    if not page_tabs:
        print("No page tabs found", file=sys.stderr)
        sys.exit(1)
    
    active_tab = page_tabs[0]
    
    # Save tab information
    with open('/tmp/translate_verification/final_page_info.json', 'w') as f:
        json.dump(active_tab, f, indent=2)
    
    print(f"✓ Captured page info: {active_tab.get('title', 'Unknown')[:50]}")
    
except Exception as e:
    print(f"⚠ Warning: Could not capture page info via CDP: {e}", file=sys.stderr)
PYTHON_EOF

# Alternative: Save the current page source using Chrome
# We'll use Ctrl+U to open source view, then save it
# This is complex, so for simplicity we'll rely on CDP and language detection of title

# Method 2: Extract visible text using xdotool and clipboard
echo "Attempting to extract visible text..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5

# Select all text and copy to clipboard (this will copy rendered text)
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+a" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+c" || true
sleep 0.5

# Paste clipboard to a text file using xclip
if command -v xclip &> /dev/null; then
    su - ga -c "DISPLAY=:1 xclip -o -selection clipboard" > "$VERIFY_DIR/final_text_content.txt" 2>/dev/null || true
    echo "✓ Extracted visible text content"
else
    echo "⚠ xclip not available, skipping text extraction"
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshot saved"
fi

# Check for translation indicators in page title or URL
echo "Checking for translation indicators..."
if [ -f "$VERIFY_DIR/final_title.txt" ]; then
    TITLE=$(cat "$VERIFY_DIR/final_title.txt")
    
    # Check if title contains English words (basic check)
    if echo "$TITLE" | grep -qi "artificial\|intelligence\|revolution"; then
        echo "✓ Detected potential English content in title"
        echo "true" > "$VERIFY_DIR/english_detected_in_title.txt"
    else
        echo "false" > "$VERIFY_DIR/english_detected_in_title.txt"
    fi
fi

echo "✅ Export complete"
echo "Verification files saved to: $VERIFY_DIR"