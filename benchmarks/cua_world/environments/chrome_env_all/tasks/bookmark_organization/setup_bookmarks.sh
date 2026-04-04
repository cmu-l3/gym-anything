#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Organization Task Setup ==="
echo "Task: Organize scattered bookmarks into logical folder structure"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Determine Chrome profile directory
CHROME_PROFILE_DIR="/home/ga/.config/google-chrome/Default"
if [ ! -d "/home/ga/.config/google-chrome" ]; then
    # Try alternative profile location used by CDP
    CHROME_PROFILE_DIR="/home/ga/.config/google-chrome-cdp/Default"
fi

# Create Chrome profile directory if it doesn't exist
mkdir -p "$CHROME_PROFILE_DIR"
chown -R ga:ga "/home/ga/.config/google-chrome" 2>/dev/null || true
chown -R ga:ga "/home/ga/.config/google-chrome-cdp" 2>/dev/null || true

# Create initial Bookmarks file with scattered, uncategorized bookmarks
BOOKMARKS_FILE="$CHROME_PROFILE_DIR/Bookmarks"
echo "Creating initial bookmarks at: $BOOKMARKS_FILE"

# Calculate timestamp for bookmarks (current time in Chrome format)
CURRENT_TIME=$(date +%s)
CHROME_TIME=$((($CURRENT_TIME + 11644473600) * 1000000))

cat > "$BOOKMARKS_FILE" << EOF
{
   "checksum": "d3c6f3c8e8f8d3c6f3c8e8f8",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "$CHROME_TIME",
               "id": "5",
               "name": "CNN",
               "type": "url",
               "url": "https://www.cnn.com"
            },
            {
               "date_added": "$CHROME_TIME",
               "id": "6",
               "name": "GitHub",
               "type": "url",
               "url": "https://github.com"
            },
            {
               "date_added": "$CHROME_TIME",
               "id": "7",
               "name": "Twitter",
               "type": "url",
               "url": "https://twitter.com"
            },
            {
               "date_added": "$CHROME_TIME",
               "id": "8",
               "name": "Stack Overflow",
               "type": "url",
               "url": "https://stackoverflow.com"
            },
            {
               "date_added": "$CHROME_TIME",
               "id": "9",
               "name": "BBC News",
               "type": "url",
               "url": "https://www.bbc.com/news"
            },
            {
               "date_added": "$CHROME_TIME",
               "id": "10",
               "name": "MDN Web Docs",
               "type": "url",
               "url": "https://developer.mozilla.org"
            },
            {
               "date_added": "$CHROME_TIME",
               "id": "11",
               "name": "Reddit",
               "type": "url",
               "url": "https://www.reddit.com"
            },
            {
               "date_added": "$CHROME_TIME",
               "id": "12",
               "name": "npm",
               "type": "url",
               "url": "https://www.npmjs.com"
            },
            {
               "date_added": "$CHROME_TIME",
               "id": "13",
               "name": "The Guardian",
               "type": "url",
               "url": "https://www.theguardian.com"
            },
            {
               "date_added": "$CHROME_TIME",
               "id": "14",
               "name": "W3C Standards",
               "type": "url",
               "url": "https://www.w3.org"
            }
         ],
         "date_added": "$CHROME_TIME",
         "date_modified": "$CHROME_TIME",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "$CHROME_TIME",
         "date_modified": "0",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "$CHROME_TIME",
         "date_modified": "0",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
EOF

# Ensure proper permissions
chown ga:ga "$BOOKMARKS_FILE"
chmod 644 "$BOOKMARKS_FILE"
echo "✓ Created bookmarks file with 10 scattered bookmarks"

# Backup bookmarks for debugging
cp "$BOOKMARKS_FILE" "$BOOKMARKS_FILE.initial_backup"
echo "✓ Created backup at: $BOOKMARKS_FILE.initial_backup"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running, if not start it
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

# Navigate to chrome://bookmarks to show bookmark manager initially
echo "Opening Bookmark Manager..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://bookmarks'" || true
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

# List initial bookmarks for debugging
echo ""
echo "Initial bookmarks in bookmark bar:"
echo "  1. CNN (news)"
echo "  2. GitHub (development)"
echo "  3. Twitter (social media)"
echo "  4. Stack Overflow (development)"
echo "  5. BBC News (news)"
echo "  6. MDN Web Docs (documentation)"
echo "  7. Reddit (social media)"
echo "  8. npm (development)"
echo "  9. The Guardian (news)"
echo " 10. W3C Standards (documentation)"
echo ""

echo "=== Setup complete ==="
echo "Chrome Bookmark Manager is open and ready."
echo "Agent should:"
echo "  1. Create folders: 'News & Media', 'Development', 'Social Media', 'Documentation'"
echo "  2. Drag/move bookmarks into appropriate folders"
echo "  3. Ensure all 10 bookmarks are organized"