#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Export Task Setup ==="
echo "Task: Export Chrome bookmarks to HTML file for backup"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install HTML parsing library for verification
pip3 install -q beautifulsoup4 lxml 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Define Chrome profile path
CHROME_PROFILE_DIR="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE_DIR"

# Create test bookmarks structure
echo "Creating test bookmarks..."
cat > "$CHROME_PROFILE_DIR/Bookmarks" << 'EOF'
{
   "checksum": "abc123",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "13360799510000000",
               "date_last_used": "0",
               "guid": "guid-google",
               "id": "5",
               "name": "Google",
               "type": "url",
               "url": "https://www.google.com"
            },
            {
               "date_added": "13360799520000000",
               "date_last_used": "0",
               "guid": "guid-github",
               "id": "6",
               "name": "GitHub",
               "type": "url",
               "url": "https://github.com"
            },
            {
               "children": [
                  {
                     "date_added": "13360799530000000",
                     "date_last_used": "0",
                     "guid": "guid-portal",
                     "id": "8",
                     "name": "Company Portal",
                     "type": "url",
                     "url": "https://portal.company.com"
                  },
                  {
                     "date_added": "13360799540000000",
                     "date_last_used": "0",
                     "guid": "guid-email",
                     "id": "9",
                     "name": "Email",
                     "type": "url",
                     "url": "https://mail.company.com"
                  }
               ],
               "date_added": "13360799550000000",
               "date_last_used": "0",
               "date_modified": "13360799540000000",
               "guid": "guid-work",
               "id": "7",
               "name": "Work",
               "type": "folder"
            },
            {
               "children": [
                  {
                     "date_added": "13360799560000000",
                     "date_last_used": "0",
                     "guid": "guid-docs",
                     "id": "11",
                     "name": "Documentation",
                     "type": "url",
                     "url": "https://docs.example.com"
                  }
               ],
               "date_added": "13360799570000000",
               "date_last_used": "0",
               "date_modified": "13360799560000000",
               "guid": "guid-ref",
               "id": "10",
               "name": "Reference",
               "type": "folder"
            }
         ],
         "date_added": "13360799500000000",
         "date_last_used": "0",
         "date_modified": "13360799570000000",
         "guid": "guid-bar",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13360799500000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "guid-other",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13360799500000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "guid-sync",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "sync_metadata": "",
   "version": 1
}
EOF

chown ga:ga "$CHROME_PROFILE_DIR/Bookmarks"
echo "✓ Test bookmarks created with 4 URLs and 2 folders"

# Ensure bookmarks bar is visible
echo "Configuring Chrome preferences..."
PREFS_FILE="$CHROME_PROFILE_DIR/Preferences"
if [ -f "$PREFS_FILE" ]; then
    # Backup existing preferences
    cp "$PREFS_FILE" "$PREFS_FILE.backup" || true
fi

# Create or update Preferences to show bookmarks bar
cat > "$PREFS_FILE" << 'EOF'
{
   "bookmark_bar": {
      "show_on_all_tabs": true
   },
   "browser": {
      "show_home_button": true
   }
}
EOF

chown ga:ga "$PREFS_FILE"

# Ensure Downloads directory exists
mkdir -p "/home/ga/Downloads"
chown ga:ga "/home/ga/Downloads"

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
echo "Chrome is ready with test bookmarks. Agent should:"
echo "  1. Press Ctrl+Shift+O to open Bookmark Manager"
echo "  2. Click three-dot menu (⋮) in Bookmark Manager"
echo "  3. Select 'Export bookmarks'"
echo "  4. Save as HTML file in Downloads"