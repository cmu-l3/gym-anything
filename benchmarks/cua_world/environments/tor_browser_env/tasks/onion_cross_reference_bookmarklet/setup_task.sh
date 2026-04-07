#!/bin/bash
# setup_task.sh for onion_cross_reference_bookmarklet
# Prepares Tor Browser in a clean state (toolbar hidden, no bookmarks, no history)

set -e
echo "=== Setting up onion_cross_reference_bookmarklet task ==="

TASK_NAME="onion_cross_reference_bookmarklet"

# Kill any existing Tor Browser instances
echo "Killing any existing Tor Browser instances..."
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
        echo "Found Tor Browser profile at: $PROFILE_DIR"
        break
    fi
done

# Clean slate: remove report file if it exists
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/pivot_workflow_report.txt 2>/dev/null || true

# Modify profile for clean test state
if [ -n "$PROFILE_DIR" ]; then
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    PLACES_DB="$PROFILE_DIR/places.sqlite"

    # Reset bookmarks toolbar visibility to hidden ("newtab" is default hidden state, "always" is visible)
    if [ -f "$PREFS_FILE" ]; then
        sed -i '/browser\.toolbars\.bookmarks\.visibility/d' "$PREFS_FILE" 2>/dev/null || true
        echo 'user_pref("browser.toolbars.bookmarks.visibility", "newtab");' >> "$PREFS_FILE"
    fi

    # Clear history and custom bookmarks to ensure agent must do the work
    if [ -f "$PLACES_DB" ]; then
        rm -f "$PLACES_DB" "${PLACES_DB}-shm" "${PLACES_DB}-wal" 2>/dev/null || true
        echo "Places database cleared."
    fi
fi

# Record task start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# Find and launch Tor Browser
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

# Wait for Tor connection (up to 5 minutes)
echo "Waiting for Tor network connection..."
ELAPSED=0
TIMEOUT=300
TOR_CONNECTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        :
    elif [ -n "$WINDOW_TITLE" ]; then
        if echo "$WINDOW_TITLE" | grep -qiE "explore|duckduckgo|privacy|search|new tab|about:blank"; then
            echo "Tor Browser connected after ${ELAPSED}s"
            TOR_CONNECTED=true
            break
        elif echo "$WINDOW_TITLE" | grep -qiE "^tor browser$"; then
            sleep 10
            WINDOW_TITLE_RECHECK=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
            if ! echo "$WINDOW_TITLE_RECHECK" | grep -qiE "connecting|establishing"; then
                TOR_CONNECTED=true
                break
            fi
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ "$TOR_CONNECTED" = "false" ]; then
    echo "ERROR: Tor Browser did not connect within ${TIMEOUT}s"
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_failed.png 2>/dev/null || true
    exit 1
fi

# Give it a few seconds to settle
sleep 5

# Maximize and Focus window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

sleep 2
# Take initial screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Task setup complete ==="