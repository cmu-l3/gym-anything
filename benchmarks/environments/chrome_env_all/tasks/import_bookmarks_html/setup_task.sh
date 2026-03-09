#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Import Bookmarks from HTML Task Setup ==="
echo "Task: Import bookmarks from HTML file using Chrome's import feature"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Create the HTML bookmarks file in Downloads folder
echo "Creating HTML bookmarks file..."
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
    <DT><H3 ADD_DATE="1234567890" LAST_MODIFIED="1234567891" PERSONAL_TOOLBAR_FOLDER="true">Development Resources</H3>
    <DL><p>
        <DT><A HREF="https://docs.python.org/3/" ADD_DATE="1234567890" ICON="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==">Python Documentation</A>
        <DT><A HREF="https://stackoverflow.com/" ADD_DATE="1234567891">Stack Overflow</A>
        <DT><A HREF="https://github.com/" ADD_DATE="1234567892">GitHub</A>
        <DT><A HREF="https://developer.mozilla.org/" ADD_DATE="1234567893">MDN Web Docs</A>
        <DT><A HREF="https://www.w3schools.com/" ADD_DATE="1234567894">W3Schools</A>
    </DL><p>
</DL><p>
EOF

chown ga:ga "$DOWNLOADS_DIR/bookmarks_to_import.html"
echo "✓ HTML bookmarks file created at: $DOWNLOADS_DIR/bookmarks_to_import.html"
echo "✓ File contains 5 bookmarks in 'Development Resources' folder"

# Verify file was created
if [ -f "$DOWNLOADS_DIR/bookmarks_to_import.html" ]; then
    FILE_SIZE=$(stat -c%s "$DOWNLOADS_DIR/bookmarks_to_import.html")
    echo "✓ File created successfully (${FILE_SIZE} bytes)"
else
    echo "✗ Error: HTML file was not created"
    exit 1
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

# Backup current bookmarks for comparison
echo "Creating backup of current bookmarks for verification..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -f "$CHROME_PROFILE/Bookmarks" ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_before_import.json
    echo "✓ Bookmarks backup created"
else
    echo "⚠ No existing bookmarks file found (this is OK for first run)"
    echo '{"roots":{"bookmark_bar":{"children":[]}}}' > /tmp/bookmarks_before_import.json
fi

echo "=== Setup complete ==="
echo ""
echo "Chrome is ready. Agent should:"
echo "  1. Navigate to chrome://settings (Ctrl+, or via menu)"
echo "  2. Search for 'import' or navigate to 'You and Google' section"
echo "  3. Click 'Import bookmarks and settings'"
echo "  4. Select 'Bookmarks HTML file' as import source"
echo "  5. Click 'Choose File' and select bookmarks_to_import.html from Downloads"
echo "  6. Confirm the import"
echo ""
echo "Expected result: 5 bookmarks imported from HTML file"