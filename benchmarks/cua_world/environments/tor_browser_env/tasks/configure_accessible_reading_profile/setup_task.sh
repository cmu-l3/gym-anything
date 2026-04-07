#!/bin/bash
# setup_task.sh - Pre-task hook for configure_accessible_reading_profile task
# Prepares Tor Browser environment with clean accessibility settings

set -e

echo "=== Setting up configure_accessible_reading_profile task ==="

TASK_NAME="configure_accessible_reading_profile"

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

# Clean target prefs from prefs.js to establish a strict baseline
PREFS_FILE="$PROFILE_DIR/prefs.js"
if [ -n "$PROFILE_DIR" ] && [ -f "$PREFS_FILE" ]; then
    echo "Resetting target accessibility preferences to factory defaults..."
    
    sed -i '/font\.minimum-size\.x-western/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/browser\.display\.document_color_use/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/browser\.display\.foreground_color/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/browser\.display\.background_color/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/browser\.anchor_color/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/browser\.display\.use_document_fonts/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/accessibility\.browsewithcaret/d' "$PREFS_FILE" 2>/dev/null || true

    echo "Preferences reset to baseline."
fi

# Clear history to ensure visit to check.torproject.org is strictly during the task
PLACES_DB="$PROFILE_DIR/places.sqlite"
if [ -n "$PROFILE_DIR" ] && [ -f "$PLACES_DB" ]; then
    echo "Clearing browsing history to ensure clean task state..."
    rm -f "$PLACES_DB" 2>/dev/null || true
    rm -f "$PLACES_DB-shm" 2>/dev/null || true
    rm -f "$PLACES_DB-wal" 2>/dev/null || true
    echo "History database cleared"
fi

# Record task start timestamp for verification
TASK_START_TIMESTAMP=$(date +%s)
echo "$TASK_START_TIMESTAMP" > /tmp/${TASK_NAME}_start_timestamp
echo "Task start timestamp: $TASK_START_TIMESTAMP"

# Find and launch Tor Browser directly
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
    echo "Warning: Direct Tor Browser not found, falling back to torbrowser-launcher"
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for Tor Browser process
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

# Wait for Tor network connection (up to 5 minutes)
echo "Waiting for Tor network connection..."
ELAPSED=0
TIMEOUT=300
TOR_CONNECTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        : # Still connecting
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
    echo "WARNING: Tor Browser may not have connected within ${TIMEOUT}s. Continuing anyway..."
fi

# Focus the Tor window and maximize it
sleep 2
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Task setup complete ==="