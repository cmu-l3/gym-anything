#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Organization Task Setup ==="
echo "Task: Organize scattered bookmarks into logical folders"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq sqlite3 python3 || true

# Wait for environment to be ready
sleep 2

# Kill any running Chrome to safely modify bookmarks
echo "Stopping Chrome if running..."
pkill -f "chrome.*remote-debugging-port" || true
sleep 2

# Setup Chrome profile with scattered bookmarks
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"

# Create initial Bookmarks file with scattered bookmarks on bookmark bar
echo "Creating initial bookmark structure..."
cat > "$CHROME_PROFILE/Bookmarks" <<'EOF'
{
   "checksum": "0000000000000000",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "13300000000000000",
               "id": "10",
               "name": "BBC News",
               "type": "url",
               "url": "https://www.bbc.com/news"
            },
            {
               "date_added": "13300000000000001",
               "id": "11",
               "name": "Amazon",
               "type": "url",
               "url": "https://www.amazon.com"
            },
            {
               "date_added": "13300000000000002",
               "id": "12",
               "name": "GitHub",
               "type": "url",
               "url": "https://github.com"
            },
            {
               "date_added": "13300000000000003",
               "id": "13",
               "name": "Twitter",
               "type": "url",
               "url": "https://twitter.com"
            },
            {
               "date_added": "13300000000000004",
               "id": "14",
               "name": "Stack Overflow",
               "type": "url",
               "url": "https://stackoverflow.com"
            },
            {
               "date_added": "13300000000000005",
               "id": "15",
               "name": "eBay",
               "type": "url",
               "url": "https://www.ebay.com"
            },
            {
               "date_added": "13300000000000006",
               "id": "16",
               "name": "Reddit",
               "type": "url",
               "url": "https://www.reddit.com"
            },
            {
               "date_added": "13300000000000007",
               "id": "17",
               "name": "MDN Web Docs",
               "type": "url",
               "url": "https://developer.mozilla.org"
            },
            {
               "date_added": "13300000000000008",
               "id": "18",
               "name": "CNN",
               "type": "url",
               "url": "https://www.cnn.com"
            },
            {
               "date_added": "13300000000000009",
               "id": "19",
               "name": "LinkedIn",
               "type": "url",
               "url": "https://www.linkedin.com"
            },
            {
               "date_added": "13300000000000010",
               "id": "20",
               "name": "Etsy",
               "type": "url",
               "url": "https://www.etsy.com"
            },
            {
               "date_added": "13300000000000011",
               "id": "21",
               "name": "TechCrunch",
               "type": "url",
               "url": "https://techcrunch.com"
            }
         ],
         "date_added": "13300000000000000",
         "date_modified": "0",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13300000000000000",
         "date_modified": "0",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13300000000000000",
         "date_modified": "0",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
EOF

# Set proper ownership
chown -R ga:ga "$CHROME_PROFILE"
chmod 644 "$CHROME_PROFILE/Bookmarks"

echo "Created 12 scattered bookmarks on bookmark bar"

# Start Chrome with the new bookmarks
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh chrome://bookmarks" &
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

# Navigate to Bookmark Manager
echo "Opening Bookmark Manager..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+shift+o" || true
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
echo "Chrome Bookmark Manager should be open with 12 scattered bookmarks"
echo "Expected folders to create: News, Shopping, Social, Dev Resources"