#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmarks Folder Organization Task Setup ==="
echo "Task: Create 'News' folder and organize bookmarks"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

echo "Setting up Chrome bookmarks..."

# Define Chrome profile path
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"

# Kill any existing Chrome instances to ensure clean state
pkill -f "google-chrome" || true
sleep 2

# Create initial bookmarks structure with 6 bookmarks in bookmark bar
# 3 news sites + 3 tech sites
echo "Creating initial bookmarks file..."
cat > "$CHROME_PROFILE/Bookmarks" << 'EOF'
{
   "checksum": "0000000000000000000000000000000000000000",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "13360799510000000",
               "guid": "00000000-0000-4000-a000-000000000001",
               "id": "6",
               "name": "BBC News",
               "type": "url",
               "url": "https://www.bbc.com/news"
            },
            {
               "date_added": "13360799520000000",
               "guid": "00000000-0000-4000-a000-000000000002",
               "id": "7",
               "name": "CNN",
               "type": "url",
               "url": "https://www.cnn.com"
            },
            {
               "date_added": "13360799530000000",
               "guid": "00000000-0000-4000-a000-000000000003",
               "id": "8",
               "name": "The Guardian",
               "type": "url",
               "url": "https://www.theguardian.com"
            },
            {
               "date_added": "13360799540000000",
               "guid": "00000000-0000-4000-a000-000000000004",
               "id": "9",
               "name": "TechCrunch",
               "type": "url",
               "url": "https://techcrunch.com"
            },
            {
               "date_added": "13360799550000000",
               "guid": "00000000-0000-4000-a000-000000000005",
               "id": "10",
               "name": "Hacker News",
               "type": "url",
               "url": "https://news.ycombinator.com"
            },
            {
               "date_added": "13360799560000000",
               "guid": "00000000-0000-4000-a000-000000000006",
               "id": "11",
               "name": "Ars Technica",
               "type": "url",
               "url": "https://arstechnica.com"
            }
         ],
         "date_added": "13360799500000000",
         "date_modified": "13360799560000000",
         "guid": "00000000-0000-4000-a000-000000000010",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13360799500000000",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000011",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13360799500000000",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000012",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
EOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"
echo "✓ Initial bookmarks created with 6 bookmarks (3 news + 3 tech)"

# Ensure bookmarks bar is visible in preferences
echo "Configuring Chrome preferences..."
PREFS_FILE="$CHROME_PROFILE/Preferences"
if [ ! -f "$PREFS_FILE" ]; then
    cat > "$PREFS_FILE" << 'EOF'
{
   "bookmark_bar": {
      "show_on_all_tabs": true
   },
   "browser": {
      "show_home_button": true,
      "check_default_browser": false
   }
}
EOF
    chown ga:ga "$PREFS_FILE"
fi

# Ensure Chrome is properly focused and ready
echo "Starting Chrome..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Starting Chrome..."
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

# Navigate to starting URL (Google as neutral starting point)
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Verify bookmarks were loaded
sleep 2
echo "Verifying bookmarks setup..."
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    BOOKMARK_COUNT=$(jq -r '.roots.bookmark_bar.children | length' "$CHROME_PROFILE/Bookmarks" 2>/dev/null || echo "0")
    echo "✓ Bookmarks file contains $BOOKMARK_COUNT bookmarks in bookmark bar"
else
    echo "⚠ Warning: Bookmarks file not found"
fi

echo "=== Setup complete ==="
echo "Chrome is ready with 6 bookmarks in bookmark bar:"
echo "  - BBC News, CNN, The Guardian (news sites)"
echo "  - TechCrunch, Hacker News, Ars Technica (tech sites)"
echo ""
echo "Agent task:"
echo "  1. Create a folder named 'News' in the bookmark bar"
echo "  2. Move the 3 news bookmarks (BBC News, CNN, The Guardian) into the News folder"
echo "  3. Keep the 3 tech bookmarks in the bookmark bar"
echo ""
echo "Methods to accomplish this:"
echo "  - Right-click on bookmark bar → Add folder → Name it 'News'"
echo "  - Drag and drop news bookmarks into the News folder"
echo "  - Or use Bookmark Manager (Ctrl+Shift+O or chrome://bookmarks/)"