#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Deduplication Task Setup ==="
echo "Task: Remove duplicate bookmarks while preserving unique URLs"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

echo "Creating bookmark structure with intentional duplicates..."

# Ensure Chrome is stopped before modifying bookmarks
echo "Stopping Chrome to safely modify bookmarks..."
pkill -f "google-chrome" || true
pkill -f "chrome.*remote-debugging" || true
sleep 2

# Determine Chrome profile path
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -d "$CHROME_PROFILE" ]; then
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ ! -d "$CHROME_PROFILE" ]; then
        # Create the directory structure
        CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
        mkdir -p "$CHROME_PROFILE"
    fi
fi

echo "Using Chrome profile: $CHROME_PROFILE"

# Create a Bookmarks file with intentional duplicates
cat > "$CHROME_PROFILE/Bookmarks" << 'EOF'
{
   "checksum": "00000000000000000000000000000000",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "13360799510000000",
               "id": "5",
               "name": "Example Site",
               "type": "url",
               "url": "https://example.com"
            },
            {
               "date_added": "13360799520000000",
               "id": "6",
               "name": "Python Documentation",
               "type": "url",
               "url": "https://docs.python.org/3/"
            },
            {
               "date_added": "13360799530000000",
               "id": "7",
               "name": "GitHub",
               "type": "url",
               "url": "https://github.com"
            },
            {
               "date_added": "13360799540000000",
               "id": "8",
               "name": "Example Duplicate",
               "type": "url",
               "url": "https://example.com"
            },
            {
               "date_added": "13360799550000000",
               "id": "9",
               "name": "MDN Web Docs",
               "type": "url",
               "url": "https://developer.mozilla.org"
            },
            {
               "children": [
                  {
                     "date_added": "13360799560000000",
                     "id": "11",
                     "name": "GitHub Work",
                     "type": "url",
                     "url": "https://github.com"
                  },
                  {
                     "date_added": "13360799570000000",
                     "id": "12",
                     "name": "Stack Overflow",
                     "type": "url",
                     "url": "https://stackoverflow.com"
                  },
                  {
                     "date_added": "13360799580000000",
                     "id": "13",
                     "name": "Python Reference",
                     "type": "url",
                     "url": "https://docs.python.org/3/"
                  }
               ],
               "date_added": "13360799500000000",
               "date_modified": "13360799580000000",
               "id": "10",
               "name": "Work",
               "type": "folder"
            },
            {
               "children": [
                  {
                     "date_added": "13360799590000000",
                     "id": "15",
                     "name": "Reddit",
                     "type": "url",
                     "url": "https://reddit.com"
                  },
                  {
                     "date_added": "13360799600000000",
                     "id": "16",
                     "name": "Developer Docs",
                     "type": "url",
                     "url": "https://developer.mozilla.org"
                  },
                  {
                     "date_added": "13360799610000000",
                     "id": "17",
                     "name": "Hacker News",
                     "type": "url",
                     "url": "https://news.ycombinator.com"
                  }
               ],
               "date_added": "13360799490000000",
               "date_modified": "13360799610000000",
               "id": "14",
               "name": "Personal",
               "type": "folder"
            }
         ],
         "date_added": "13360799480000000",
         "date_modified": "13360799610000000",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13360799480000000",
         "date_modified": "0",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13360799480000000",
         "date_modified": "0",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
EOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"
chmod 644 "$CHROME_PROFILE/Bookmarks"

echo "✓ Bookmarks file created with duplicates:"
echo "  - Total bookmarks: 12"
echo "  - Unique URLs: 7"
echo "  - Duplicates to remove: 5"
echo ""
echo "Duplicate summary:"
echo "  - https://example.com appears 2 times"
echo "  - https://docs.python.org/3/ appears 2 times"
echo "  - https://github.com appears 2 times"
echo "  - https://developer.mozilla.org appears 2 times"

# Start Chrome with bookmarks
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
sleep 5

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
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

# Navigate to about:blank to start clean
echo "Navigating to about:blank"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'about:blank'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is ready with duplicate bookmarks loaded."
echo ""
echo "Agent should:"
echo "  1. Press Ctrl+Shift+O to open Bookmark Manager"
echo "  2. Identify duplicate URLs across all folders"
echo "  3. Delete duplicate entries (keep one instance of each URL)"
echo "  4. Verify no duplicates remain"
echo ""
echo "Expected final state: 7 unique bookmarks (reduced from 12)"