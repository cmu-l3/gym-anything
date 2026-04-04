#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmark Import from HTML Task Setup ==="
echo "Task: Import bookmarks from HTML file into Chrome bookmark system"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Create the bookmark HTML file in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
mkdir -p "$DOWNLOADS_DIR"

echo "Creating bookmark HTML file..."
cat > "$DOWNLOADS_DIR/bookmarks_import.html" << 'EOF'
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<!-- This is an automatically generated file.
     It will be read and overwritten.
     DO NOT EDIT! -->
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><H3>Imported Resources</H3>
    <DL><p>
        <DT><A HREF="https://www.wikipedia.org" ADD_DATE="1234567890" LAST_MODIFIED="1234567890">Wikipedia</A>
        <DT><A HREF="https://www.github.com" ADD_DATE="1234567890" LAST_MODIFIED="1234567890">GitHub</A>
    </DL><p>
    <DT><H3>News Sites</H3>
    <DL><p>
        <DT><A HREF="https://news.ycombinator.com" ADD_DATE="1234567890" LAST_MODIFIED="1234567890">Hacker News</A>
        <DT><A HREF="https://www.reddit.com" ADD_DATE="1234567890" LAST_MODIFIED="1234567890">Reddit</A>
    </DL><p>
    <DT><A HREF="https://www.example.com" ADD_DATE="1234567890" LAST_MODIFIED="1234567890">Example Domain</A>
</DL><p>
EOF

# Set proper ownership
chown ga:ga "$DOWNLOADS_DIR/bookmarks_import.html"
chmod 644 "$DOWNLOADS_DIR/bookmarks_import.html"

echo "✓ Bookmark HTML file created at: $DOWNLOADS_DIR/bookmarks_import.html"
ls -lh "$DOWNLOADS_DIR/bookmarks_import.html"

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

echo "=== Setup complete ==="
echo "Chrome is ready. Bookmark HTML file is in Downloads folder."
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://bookmarks/"
echo "  2. Click the three-dot menu in Bookmark Manager"
echo "  3. Select 'Import bookmarks'"
echo "  4. Navigate to Downloads folder"
echo "  5. Select bookmarks_import.html"
echo "  6. Confirm the import"