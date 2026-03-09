#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Reading List Task Setup: reading_list_articles@1 ==="
echo "Task: Add 3 articles to Chrome's Reading List for later reading"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python JSON libraries if needed
pip3 install -q jsonschema 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create article URLs file for task instructions
echo "Creating article URLs reference..."
cat > /tmp/reading_list_urls.txt << 'EOF'
https://en.wikipedia.org/wiki/Artificial_intelligence
https://www.nature.com/articles/d41586-023-00288-7
https://stackoverflow.blog/2023/01/09/beyond-the-pixel-perfect-mockup/
EOF

echo "✓ Article URLs created at: /tmp/reading_list_urls.txt"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to the starting URL (Google homepage)
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Close any extra tabs to start fresh
echo "Closing extra tabs to start clean..."
for i in {1..5}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        echo "Found $TAB_COUNT tabs, closing extras..."
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.5
    else
        break
    fi
done

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    INITIAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Starting with $INITIAL_TAB_COUNT tab(s)"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Check if side panel button is available (Reading List access point)
echo "Checking Chrome UI elements..."
sleep 1

echo "=== Setup complete ==="
echo "Chrome is ready at Google homepage"
echo ""
echo "Agent task instructions:"
echo "  1. Navigate to an article URL (e.g., Wikipedia, news article, blog post)"
echo "  2. Right-click on the page and select 'Add to Reading List'"
echo "     OR click the star/bookmark icon and choose 'Add to Reading List'"
echo "     OR open the side panel (top-right) and use 'Add to Reading List'"
echo "  3. Repeat for 2 more different articles (total: 3 articles)"
echo ""
echo "  Note: Use 'Add to Reading List' feature, NOT regular bookmarks!"
echo "  Reading List is Chrome's built-in 'read later' feature for temporary article saving."