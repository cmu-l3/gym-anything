#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Selective Privacy Clear Task Setup ==="
echo "Task: Clear sensitive browsing data while preserving important saved information"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python libraries for verification
pip3 install -q requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

echo "Setting up Chrome with browsing data..."

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

# Function to navigate to URL
navigate_to_url() {
    local url="$1"
    echo "Navigating to: $url"
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 3
}

# Create browsing history by visiting several sites
echo "Creating browsing history..."
navigate_to_url "https://www.wikipedia.org"
navigate_to_url "https://www.github.com"
navigate_to_url "https://news.ycombinator.com"
navigate_to_url "https://www.reddit.com"
navigate_to_url "https://www.stackoverflow.com"

# Create bookmarks programmatically
echo "Creating bookmarks to preserve..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"

# Create Bookmarks file with some pre-existing bookmarks
cat > "$CHROME_PROFILE/Bookmarks" << 'BOOKMARKS_EOF'
{
   "checksum": "0123456789abcdef",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "13360799510000000",
               "guid": "00000000-0000-4000-a000-000000000001",
               "id": "5",
               "name": "Important Work Sites",
               "type": "folder",
               "children": [
                  {
                     "date_added": "13360799510000000",
                     "guid": "00000000-0000-4000-a000-000000000002",
                     "id": "6",
                     "name": "Company Portal",
                     "type": "url",
                     "url": "https://portal.company.com"
                  },
                  {
                     "date_added": "13360799510000000",
                     "guid": "00000000-0000-4000-a000-000000000003",
                     "id": "7",
                     "name": "Project Management",
                     "type": "url",
                     "url": "https://jira.company.com"
                  }
               ]
            },
            {
               "date_added": "13360799520000000",
               "guid": "00000000-0000-4000-a000-000000000004",
               "id": "8",
               "name": "Personal Resources",
               "type": "folder",
               "children": [
                  {
                     "date_added": "13360799520000000",
                     "guid": "00000000-0000-4000-a000-000000000005",
                     "id": "9",
                     "name": "Email",
                     "type": "url",
                     "url": "https://mail.google.com"
                  },
                  {
                     "date_added": "13360799520000000",
                     "guid": "00000000-0000-4000-a000-000000000006",
                     "id": "10",
                     "name": "Banking",
                     "type": "url",
                     "url": "https://bank.example.com"
                  }
               ]
            },
            {
               "date_added": "13360799530000000",
               "guid": "00000000-0000-4000-a000-000000000007",
               "id": "11",
               "name": "GitHub",
               "type": "url",
               "url": "https://github.com"
            }
         ],
         "date_added": "13360799500000000",
         "date_modified": "13360799530000000",
         "guid": "00000000-0000-4000-a000-000000000000",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13360799500000000",
         "date_modified": "0",
         "guid": "00000000-0000-4000-b000-000000000000",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13360799500000000",
         "date_modified": "0",
         "guid": "00000000-0000-4000-c000-000000000000",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
BOOKMARKS_EOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"
echo "✓ Bookmarks created"

# Restart Chrome to load bookmarks
echo "Restarting Chrome to load bookmarks..."
pkill -f "google-chrome" || true
sleep 2
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
sleep 5

# Focus Chrome again
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -n "$wid" ]; then
    wmctrl -i -a $wid || true
    sleep 1
fi

# Visit a few more sites to ensure history and cookies are created
echo "Creating additional browsing data..."
navigate_to_url "https://www.python.org"
navigate_to_url "https://www.google.com"

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Verify that data was created
echo "Verifying pre-populated data..."
if [ -f "$CHROME_PROFILE/History" ]; then
    HISTORY_COUNT=$(sqlite3 "$CHROME_PROFILE/History" "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "0")
    echo "✓ History database has $HISTORY_COUNT entries"
fi

if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    echo "✓ Bookmarks file exists"
fi

echo "=== Setup complete ==="
echo "Chrome has browsing data that needs to be cleared:"
echo "  - Browsing history (multiple sites visited)"
echo "  - Cookies from various domains"
echo "  - Cached images and files"
echo ""
echo "Chrome has data that should be PRESERVED:"
echo "  - Bookmarks (Important Work Sites, Personal Resources folders)"
echo "  - Saved passwords (if any)"
echo "  - Autofill data (if any)"
echo ""
echo "Agent should:"
echo "  1. Navigate to Settings (chrome://settings or via menu)"
echo "  2. Go to 'Privacy and security' section"
echo "  3. Click 'Clear browsing data'"
echo "  4. Select 'All time' from time range dropdown"
echo "  5. CHECK: Browsing history, Cookies, Cached images"
echo "  6. UNCHECK: Passwords, Autofill (if visible)"
echo "  7. Click 'Clear data' button"