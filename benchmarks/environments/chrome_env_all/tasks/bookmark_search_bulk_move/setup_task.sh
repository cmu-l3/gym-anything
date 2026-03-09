#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Search and Bulk Move Task Setup ==="
echo "Task: Search bookmarks, create folder, and bulk organize"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Stop Chrome if running to modify bookmarks safely
echo "Stopping Chrome to prepare bookmarks..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# Ensure Chrome profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome-cdp"

# Create initial bookmarks with scattered tech news URLs
echo "Creating sample bookmarks for task..."
cat > "$CHROME_PROFILE/Bookmarks" << 'EOF'
{
   "checksum": "abcdef1234567890",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "13360799510000000",
               "guid": "00000000-0000-4000-a000-000000000001",
               "id": "5",
               "name": "TechCrunch AI News",
               "type": "url",
               "url": "https://techcrunch.com/category/artificial-intelligence/"
            },
            {
               "date_added": "13360799520000000",
               "guid": "00000000-0000-4000-a000-000000000002",
               "id": "6",
               "name": "Google",
               "type": "url",
               "url": "https://www.google.com/"
            },
            {
               "date_added": "13360799530000000",
               "guid": "00000000-0000-4000-a000-000000000003",
               "id": "7",
               "name": "The Verge Tech",
               "type": "url",
               "url": "https://www.theverge.com/tech"
            },
            {
               "date_added": "13360799540000000",
               "guid": "00000000-0000-4000-a000-000000000004",
               "id": "8",
               "name": "GitHub",
               "type": "url",
               "url": "https://github.com/"
            },
            {
               "date_added": "13360799550000000",
               "guid": "00000000-0000-4000-a000-000000000005",
               "id": "9",
               "name": "TechCrunch Startups",
               "type": "url",
               "url": "https://techcrunch.com/category/startups/"
            },
            {
               "date_added": "13360799560000000",
               "guid": "00000000-0000-4000-a000-000000000006",
               "id": "10",
               "name": "Stack Overflow",
               "type": "url",
               "url": "https://stackoverflow.com/"
            },
            {
               "date_added": "13360799570000000",
               "guid": "00000000-0000-4000-a000-000000000007",
               "id": "11",
               "name": "Verge Science",
               "type": "url",
               "url": "https://www.theverge.com/science"
            },
            {
               "date_added": "13360799580000000",
               "guid": "00000000-0000-4000-a000-000000000008",
               "id": "12",
               "name": "Wikipedia",
               "type": "url",
               "url": "https://www.wikipedia.org/"
            }
         ],
         "date_added": "13360799500000000",
         "date_modified": "13360799580000000",
         "guid": "00000000-0000-4000-a000-000000000000",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13360799500000000",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000001",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13360799500000000",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000002",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
EOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"
echo "✓ Created bookmarks file with scattered tech news bookmarks"
echo "  - TechCrunch AI News"
echo "  - TechCrunch Startups"
echo "  - The Verge Tech"
echo "  - Verge Science"
echo "  - Plus 4 non-tech bookmarks"

# Start Chrome with bookmarks bar visible
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
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

# Navigate to Google homepage (neutral starting point)
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

# Take a screenshot of initial state
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/initial_screenshot.png" 2>/dev/null || true
    echo "Initial screenshot saved"
fi

echo "=== Setup complete ==="
echo "Chrome is ready with scattered bookmarks."
echo ""
echo "Agent task:"
echo "  1. Press Ctrl+Shift+O to open Bookmark Manager"
echo "  2. Search for 'techcrunch' and 'verge' bookmarks"
echo "  3. Select all matching bookmarks (use Ctrl+Click for multi-select)"
echo "  4. Create new folder 'Tech News' in bookmark bar"
echo "  5. Move all selected bookmarks into 'Tech News' folder"
echo ""
echo "Expected result: 4 bookmarks (2 TechCrunch + 2 Verge) organized in 'Tech News' folder"