#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmarks Import from HTML Task Setup ==="
echo "Task: Import bookmarks from HTML file into Chrome Bookmark Manager"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Create the bookmarks HTML file in Downloads folder
echo "Creating bookmarks HTML file for import..."
DOWNLOADS_DIR="/home/ga/Downloads"
mkdir -p "$DOWNLOADS_DIR"

cat > "$DOWNLOADS_DIR/bookmarks_to_import.html" << 'EOF'
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<!-- This is an automatically generated file.
     It will be read and overwritten.
     DO NOT EDIT! -->
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><H3 ADD_DATE="1640000000" LAST_MODIFIED="1640000000">Development Resources</H3>
    <DL><p>
        <DT><A HREF="https://github.com" ADD_DATE="1640000001" ICON="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==">GitHub</A>
        <DT><A HREF="https://stackoverflow.com" ADD_DATE="1640000002">Stack Overflow</A>
        <DT><A HREF="https://developer.mozilla.org" ADD_DATE="1640000003">MDN Web Docs</A>
    </DL><p>
    <DT><H3 ADD_DATE="1640000100" LAST_MODIFIED="1640000100">Design Tools</H3>
    <DL><p>
        <DT><A HREF="https://figma.com" ADD_DATE="1640000101">Figma</A>
        <DT><A HREF="https://dribbble.com" ADD_DATE="1640000102">Dribbble</A>
        <DT><A HREF="https://behance.net" ADD_DATE="1640000103">Behance</A>
    </DL><p>
    <DT><H3 ADD_DATE="1640000200" LAST_MODIFIED="1640000200">Productivity</H3>
    <DL><p>
        <DT><A HREF="https://notion.so" ADD_DATE="1640000201">Notion</A>
        <DT><A HREF="https://trello.com" ADD_DATE="1640000202">Trello</A>
        <DT><A HREF="https://asana.com" ADD_DATE="1640000203">Asana</A>
    </DL><p>
</DL><p>
EOF

chown ga:ga "$DOWNLOADS_DIR/bookmarks_to_import.html"
chmod 644 "$DOWNLOADS_DIR/bookmarks_to_import.html"
echo "✓ Bookmarks HTML file created at: $DOWNLOADS_DIR/bookmarks_to_import.html"

# Verify file was created correctly
if [ -f "$DOWNLOADS_DIR/bookmarks_to_import.html" ]; then
    FILE_SIZE=$(stat -f%z "$DOWNLOADS_DIR/bookmarks_to_import.html" 2>/dev/null || stat -c%s "$DOWNLOADS_DIR/bookmarks_to_import.html" 2>/dev/null || echo "0")
    echo "✓ File size: $FILE_SIZE bytes"
else
    echo "⚠ Warning: Bookmarks HTML file was not created successfully"
fi

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

# Check bookmarks bar visibility setting
echo "Checking Chrome bookmarks bar visibility..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    # Backup preferences
    cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup" || true
    echo "✓ Chrome preferences backed up"
fi

echo "=== Setup complete ==="
echo "Chrome is ready at: https://www.google.com"
echo "Bookmarks HTML file ready at: $DOWNLOADS_DIR/bookmarks_to_import.html"
echo ""
echo "Agent should now:"
echo "  1. Press Ctrl+Shift+O to open Bookmark Manager"
echo "  2. Click the three-dot menu (⋮) in Bookmark Manager"
echo "  3. Select 'Import bookmarks'"
echo "  4. Navigate to Downloads and select 'bookmarks_to_import.html'"
echo "  5. Click 'Open' to import the bookmarks"