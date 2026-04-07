#!/bin/bash
# setup_task.sh for configure_keyword_search_shortcuts task
# Prepares a clean Tor Browser state with no pre-existing custom bookmarks

set -e
echo "=== Setting up configure_keyword_search_shortcuts task ==="

TASK_NAME="configure_keyword_search_shortcuts"

# Kill any existing Tor Browser instances
echo "Killing any existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# Find Tor Browser profile directory
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "Found Tor Browser profile at: $PROFILE_DIR"
        break
    fi
done

# Clear history database to prevent false positives and reset bookmarks
PLACES_DB="$PROFILE_DIR/places.sqlite"
if [ -n "$PROFILE_DIR" ] && [ -f "$PLACES_DB" ]; then
    echo "Clearing browsing history and custom bookmarks to ensure clean task state..."
    rm -f "$PLACES_DB" 2>/dev/null || true
    rm -f "$PLACES_DB-shm" 2>/dev/null || true
    rm -f "$PLACES_DB-wal" 2>/dev/null || true
    echo "History database cleared"
fi

# Record task start timestamp
TASK_START_TIMESTAMP=$(date +%s)
echo "$TASK_START_TIMESTAMP" > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $TASK_START_TIMESTAMP"

# Create task info file for reference
cat > /home/ga/TASK_INFO.txt << 'EOF'
TASK: Configure Keyword Search Shortcuts

Create 3 keyword search bookmarks in Tor Browser:
1. Open Bookmark Manager (Ctrl+Shift+O)
2. Create folder "OSINT Search Tools"
3. Create bookmark: Name="Ahmia Onion Search", URL="https://ahmia.fi/search/?q=%s", Keyword="@ahmia"
4. Create bookmark: Name="DuckDuckGo Private", URL="https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/?q=%s", Keyword="@ddg"
5. Create bookmark: Name="Wayback Machine Lookup", URL="https://web.archive.org/web/*/%s", Keyword="@archive"

After creating them, test by typing in the URL bar:
@ddg tor project news
(Press Enter and wait for results)
EOF
chown ga:ga /home/ga/TASK_INFO.txt

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

echo "Launching Tor Browser from: $TOR_BROWSER_DIR"
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for process
echo "Waiting for Tor Browser process..."
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

# Wait for window
echo "Waiting for Tor Browser window..."
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting|download"; then
        echo "Tor Browser window appeared after ${ELAPSED}s"
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

if [ "$TOR_CONNECTED" = "false" ]; then
    echo "WARNING: Tor may not have connected within ${TIMEOUT}s. Continuing anyway..."
fi

sleep 5

# Focus window and maximize
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
# Take initial state screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== setup complete ==="