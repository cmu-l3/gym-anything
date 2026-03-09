#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Export Task Setup ==="
echo "Task: Export Chrome bookmarks to HTML file for backup"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install HTML parsing libraries for verifier
pip3 install -q beautifulsoup4 lxml 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Populate Chrome bookmarks with known structure
echo "Populating Chrome with test bookmarks..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"

# Create a well-structured bookmarks file with known URLs and folders
cat > "$CHROME_PROFILE/Bookmarks" << 'EOF'
{
   "checksum": "c6f4cf8f9e0e8e8b8d8c8b8a8980706050403020",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "13336699200000000",
               "date_last_used": "0",
               "guid": "00000000-0000-4000-a000-000000000001",
               "id": "5",
               "name": "Google",
               "type": "url",
               "url": "https://www.google.com/"
            },
            {
               "date_added": "13336699300000000",
               "date_last_used": "0",
               "guid": "00000000-0000-4000-a000-000000000002",
               "id": "6",
               "name": "YouTube",
               "type": "url",
               "url": "https://www.youtube.com/"
            },
            {
               "children": [
                  {
                     "date_added": "13336699400000000",
                     "date_last_used": "0",
                     "guid": "00000000-0000-4000-a000-000000000003",
                     "id": "8",
                     "name": "GitHub",
                     "type": "url",
                     "url": "https://github.com/"
                  },
                  {
                     "date_added": "13336699500000000",
                     "date_last_used": "0",
                     "guid": "00000000-0000-4000-a000-000000000004",
                     "id": "9",
                     "name": "Stack Overflow",
                     "type": "url",
                     "url": "https://stackoverflow.com/"
                  },
                  {
                     "date_added": "13336699600000000",
                     "date_last_used": "0",
                     "guid": "00000000-0000-4000-a000-000000000005",
                     "id": "10",
                     "name": "GitLab",
                     "type": "url",
                     "url": "https://gitlab.com/"
                  }
               ],
               "date_added": "13336699350000000",
               "date_modified": "13336699600000000",
               "guid": "00000000-0000-4000-a000-000000000006",
               "id": "7",
               "name": "Development",
               "type": "folder"
            },
            {
               "children": [
                  {
                     "date_added": "13336699700000000",
                     "date_last_used": "0",
                     "guid": "00000000-0000-4000-a000-000000000007",
                     "id": "12",
                     "name": "BBC News",
                     "type": "url",
                     "url": "https://www.bbc.com/news"
                  },
                  {
                     "date_added": "13336699800000000",
                     "date_last_used": "0",
                     "guid": "00000000-0000-4000-a000-000000000008",
                     "id": "13",
                     "name": "Reuters",
                     "type": "url",
                     "url": "https://www.reuters.com/"
                  }
               ],
               "date_added": "13336699650000000",
               "date_modified": "13336699800000000",
               "guid": "00000000-0000-4000-a000-000000000009",
               "id": "11",
               "name": "News",
               "type": "folder"
            }
         ],
         "date_added": "13336699100000000",
         "date_modified": "13336699800000000",
         "guid": "00000000-0000-4000-a000-000000000010",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [
            {
               "date_added": "13336699900000000",
               "date_last_used": "0",
               "guid": "00000000-0000-4000-a000-000000000011",
               "id": "15",
               "name": "Wikipedia",
               "type": "url",
               "url": "https://www.wikipedia.org/"
            },
            {
               "date_added": "13336700000000000",
               "date_last_used": "0",
               "guid": "00000000-0000-4000-a000-000000000012",
               "id": "16",
               "name": "MDN Web Docs",
               "type": "url",
               "url": "https://developer.mozilla.org/"
            }
         ],
         "date_added": "13336699100000000",
         "date_modified": "13336700000000000",
         "guid": "00000000-0000-4000-a000-000000000013",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13336699100000000",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000014",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
EOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"
echo "✓ Test bookmarks created with known structure"
echo "  - 2 bookmarks in bar (Google, YouTube)"
echo "  - Development folder with 3 bookmarks"
echo "  - News folder with 2 bookmarks"
echo "  - 2 bookmarks in Other bookmarks"

# Ensure Downloads directory exists and is empty of previous exports
DOWNLOADS_DIR="/home/ga/Downloads"
mkdir -p "$DOWNLOADS_DIR"
rm -f "$DOWNLOADS_DIR/bookmarks_backup.html" "$DOWNLOADS_DIR/bookmarks_"*.html 2>/dev/null || true
chown -R ga:ga "$DOWNLOADS_DIR"
echo "✓ Downloads directory prepared"

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

# Navigate to starting URL (Google homepage)
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

echo "=== Setup complete ==="
echo "Chrome is ready with pre-populated bookmarks."
echo ""
echo "Agent should:"
echo "  1. Open Bookmark Manager (Ctrl+Shift+O)"
echo "  2. Click the three-dot menu (Organize)"
echo "  3. Select 'Export bookmarks'"
echo "  4. Save as 'bookmarks_backup.html' in Downloads folder"