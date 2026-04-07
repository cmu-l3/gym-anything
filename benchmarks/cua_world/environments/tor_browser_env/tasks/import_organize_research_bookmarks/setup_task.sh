#!/bin/bash
set -e
echo "=== Setting up import_organize_research_bookmarks task ==="

TASK_NAME="import_organize_research_bookmarks"

# Kill any existing Tor Browser instances
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# Find Tor Browser profile
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# Clear places.sqlite to ensure clean slate (anti-gaming)
if [ -n "$PROFILE_DIR" ]; then
    rm -f "$PROFILE_DIR/places.sqlite" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-wal" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-shm" 2>/dev/null || true
    echo "Cleared places.sqlite for a clean task state"
fi

# Ensure Documents exists
sudo -u ga mkdir -p /home/ga/Documents

# Create the bookmarks HTML file based on the real organizations
cat > /home/ga/Documents/research_bookmarks.html << 'EOF'
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks Menu</H1>
<DL><p>
    <DT><H3>Digital Archives</H3>
    <DL><p>
        <DT><A HREF="https://archive.org/">Internet Archive</A>
        <DT><A HREF="https://web.archive.org/">Wayback Machine</A>
        <DT><A HREF="https://www.europeana.eu/">Europeana Digital Library</A>
    </DL><p>
    <DT><H3>Press Freedom Organizations</H3>
    <DL><p>
        <DT><A HREF="https://rsf.org/">Reporters Without Borders</A>
        <DT><A HREF="https://cpj.org/">Committee to Protect Journalists</A>
        <DT><A HREF="https://www.eff.org/">Electronic Frontier Foundation</A>
        <DT><A HREF="https://freedom.press/">Freedom of the Press Foundation</A>
    </DL><p>
    <DT><H3>Academic Resources</H3>
    <DL><p>
        <DT><A HREF="https://arxiv.org/">arXiv Preprint Server</A>
        <DT><A HREF="https://scholar.google.com/">Google Scholar</A>
        <DT><A HREF="https://doaj.org/">Directory of Open Access Journals</A>
    </DL><p>
    <DT><H3>Tor Network Resources</H3>
    <DL><p>
        <DT><A HREF="https://www.torproject.org/">The Tor Project</A>
        <DT><A HREF="https://check.torproject.org/">Tor Connection Check</A>
        <DT><A HREF="https://support.torproject.org/">Tor Support Portal</A>
    </DL><p>
</DL><p>
EOF
chown ga:ga /home/ga/Documents/research_bookmarks.html

# Record task start timestamp (used to verify entries were added during task)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $TASK_START"

# Launch Tor Browser
TOR_BROWSER_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then
        TOR_BROWSER_DIR="$candidate"
        break
    fi
done

echo "Launching Tor Browser..."
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for process
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f "firefox.*TorBrowser\|tor-browser" > /dev/null; then
        echo "Tor Browser process started after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for Tor connection
echo "Waiting for Tor connection..."
ELAPSED=0
TIMEOUT=300
TOR_CONNECTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if [ -n "$WINDOW_TITLE" ] && ! echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        if echo "$WINDOW_TITLE" | grep -qiE "explore|duckduckgo|privacy|search|new tab|about:blank"; then
            TOR_CONNECTED=true
            break
        elif echo "$WINDOW_TITLE" | grep -qiE "^tor browser$"; then
            sleep 10
            TOR_CONNECTED=true
            break
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 5

# Focus and maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete ==="