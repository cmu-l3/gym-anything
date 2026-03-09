#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Groups Organization Task Setup ==="
echo "Task: Organize multiple tabs into color-coded, named groups"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for potential OCR/image analysis
pip3 install -q pillow numpy 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
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

# Close any existing tabs to start fresh
echo "Closing existing tabs..."
for i in {1..10}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.3
    else
        break
    fi
done

sleep 1

# Open diverse set of tabs for grouping task
echo "Opening diverse tabs for organization task..."

# Tab 1: MDN Web Docs (Documentation category)
echo "Opening tab 1: MDN Web Docs"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://developer.mozilla.org/en-US/'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 2: Python Documentation (Documentation category)
echo "Opening tab 2: Python Documentation"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://docs.python.org/3/'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 3: Stack Overflow (Documentation category)
echo "Opening tab 3: Stack Overflow"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://stackoverflow.com/'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 4: Gmail (Social/Communication category)
echo "Opening tab 4: Gmail"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://mail.google.com/'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 5: Reddit (Social/Communication category)
echo "Opening tab 5: Reddit"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.reddit.com/'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 6: Amazon (Shopping category)
echo "Opening tab 6: Amazon"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.amazon.com/'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 7: eBay (Shopping category)
echo "Opening tab 7: eBay"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.ebay.com/'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 8: Hacker News (News category)
echo "Opening tab 8: Hacker News"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://news.ycombinator.com/'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 9: BBC News (News category)
echo "Opening tab 9: BBC News"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.bbc.com/news'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Focus first tab to start the task
echo "Returning to first tab..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+1" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    INITIAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Opened $INITIAL_TAB_COUNT tab(s)"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Create helper script to extract tab group information
echo "Creating tab group extraction script..."
cat > /tmp/extract_tab_groups.js << 'EOF'
// JavaScript to extract tab group information
// This will be injected into Chrome DevTools console
(async () => {
  const tabs = await chrome.tabs.query({});
  const groups = await chrome.tabGroups.query({});
  
  const groupData = groups.map(group => ({
    id: group.id,
    title: group.title || '',
    color: group.color,
    collapsed: group.collapsed,
    windowId: group.windowId
  }));
  
  const tabData = tabs.map(tab => ({
    id: tab.id,
    title: tab.title,
    url: tab.url,
    groupId: tab.groupId || -1,
    windowId: tab.windowId,
    index: tab.index
  }));
  
  const result = {
    groups: groupData,
    tabs: tabData,
    timestamp: new Date().toISOString()
  };
  
  console.log(JSON.stringify(result));
  return result;
})();
EOF

echo "=== Setup complete ==="
echo "Chrome is ready with 9 diverse tabs opened:"
echo "  - Documentation: MDN, Python Docs, Stack Overflow"
echo "  - Social: Gmail, Reddit"
echo "  - Shopping: Amazon, eBay"
echo "  - News: Hacker News, BBC News"
echo ""
echo "Agent should now:"
echo "  1. Right-click on tabs to create groups"
echo "  2. Add tabs to new groups with meaningful names"
echo "  3. Assign distinct colors to each group"
echo "  4. Organize tabs into 3-4 logical categories"