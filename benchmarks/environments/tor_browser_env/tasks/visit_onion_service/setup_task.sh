#!/bin/bash
# setup_task.sh - Pre-task hook for visit_onion_service task
# Prepares Tor Browser environment for visiting an onion service

set -e

echo "=== Setting up visit_onion_service task ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# Kill any existing Tor Browser instances
echo "Killing any existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -9 -u ga -f "torbrowser" 2>/dev/null || true
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

# CRITICAL: Clear history database to prevent false positives from previous runs
# This ensures the task can only pass if the agent actually visits the onion service
PLACES_DB="$PROFILE_DIR/places.sqlite"
if [ -n "$PROFILE_DIR" ] && [ -f "$PLACES_DB" ]; then
    echo "Clearing browsing history to ensure clean task state..."
    # Remove places.sqlite to clear all history
    rm -f "$PLACES_DB" 2>/dev/null || true
    rm -f "$PLACES_DB-shm" 2>/dev/null || true
    rm -f "$PLACES_DB-wal" 2>/dev/null || true
    echo "History database cleared"
fi

# Record task start timestamp for session verification
TASK_START_TIMESTAMP=$(date +%s)
echo "$TASK_START_TIMESTAMP" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START_TIMESTAMP"

# Initial history count will be 0 after clearing
echo "0" > /tmp/initial_history_count
echo "false" > /tmp/onion_already_visited

# Ensure Downloads directory exists
sudo -u ga mkdir -p /home/ga/Downloads

# Create task info file for reference
cat > /home/ga/TASK_INFO.txt << 'EOF'
TASK: Visit Onion Service

Your task is to:
1. Open Tor Browser (it will be launched for you)
2. Wait for the Tor network connection to be established
3. Navigate to DuckDuckGo's onion service:
   https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/
4. Search for "Tor Project"
5. Verify the search results page loads

Note: Onion services may take longer to load than regular websites.
Be patient as the connection is established through multiple Tor relays.
EOF
chown ga:ga /home/ga/TASK_INFO.txt

# Find and launch Tor Browser directly (not via torbrowser-launcher which may have outdated URLs)
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
    # Launch directly from installed location
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    # Fallback to torbrowser-launcher
    echo "Warning: Direct Tor Browser not found, falling back to torbrowser-launcher"
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for Tor Browser to start (it takes longer than regular Firefox)
echo "Waiting for Tor Browser to start..."
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f "firefox.*TorBrowser\|tor-browser" > /dev/null; then
        echo "Tor Browser process started after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: Tor Browser may not have started within timeout"
fi

# Wait for Tor Browser window to appear (any window, including download dialogs)
echo "Waiting for Tor Browser window..."
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting|download"; then
        echo "Tor Browser window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

# CRITICAL: Wait for Tor to FULLY CONNECT before taking task_start screenshot
# The task description says "Tor Browser will launch and connect" - we must ensure it's connected
# Detection strategy:
# 1. Wait for window title to NOT contain "Connecting", "Establishing", "Starting", "Download"
# 2. Then wait additional time for page to fully render
echo "Waiting for Tor Browser to fully connect to the Tor network..."
ELAPSED=0
TIMEOUT=300  # 5 minutes max for Tor connection (can be slow)
TOR_CONNECTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")

    # Check for connecting/establishing states that we need to wait for
    if echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        # Still connecting
        :
    elif [ -n "$WINDOW_TITLE" ]; then
        # Window title exists and doesn't contain connecting indicators
        # Check for positive indicators of connection
        if echo "$WINDOW_TITLE" | grep -qiE "explore|duckduckgo|privacy|search|new tab"; then
            echo "Tor Browser fully connected (positive indicator) after ${ELAPSED}s"
            echo "Window title: $WINDOW_TITLE"
            TOR_CONNECTED=true
            break
        elif echo "$WINDOW_TITLE" | grep -qiE "^tor browser$"; then
            # Just "Tor Browser" - might be connected, wait a bit more to be sure
            echo "Window shows 'Tor Browser' - waiting to confirm connection..."
            sleep 10
            # Re-check after waiting
            WINDOW_TITLE_RECHECK=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
            if ! echo "$WINDOW_TITLE_RECHECK" | grep -qiE "connecting|establishing"; then
                echo "Tor Browser appears connected after ${ELAPSED}s"
                echo "Window title: $WINDOW_TITLE_RECHECK"
                TOR_CONNECTED=true
                break
            fi
        fi
    fi

    sleep 3
    ELAPSED=$((ELAPSED + 3))

    # Show progress every 30 seconds
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        echo "Still waiting for Tor connection... (${ELAPSED}s elapsed)"
        echo "Current window title: $WINDOW_TITLE"
    fi
done

if [ "$TOR_CONNECTED" = "false" ]; then
    echo "ERROR: Tor Browser did not connect to the Tor network within ${TIMEOUT}s"
    echo "Task cannot start without a connected browser."
    echo "This is a HARD FAILURE - the task description promises a connected browser."
    # Take a screenshot for debugging before failing
    DISPLAY=:1 scrot /tmp/task_start_failed.png 2>/dev/null || true
    exit 1
fi

# Additional wait to ensure page is FULLY RENDERED after connection
# This is important because the page content loads after the connection indicator changes
echo "Allowing additional time for page to fully render..."
sleep 15

# Focus Tor Browser window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    echo "Focused Tor Browser window: $WINDOW_ID"
fi

# Verify the window title shows connected state before taking screenshot
FINAL_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
echo "Final window title before task_start screenshot: $FINAL_WINDOW_TITLE"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

# Log the connection state for debugging
echo "Task start state verification:"
echo "  - Window title: $FINAL_WINDOW_TITLE"
echo "  - Tor connected: $TOR_CONNECTED"

echo "=== visit_onion_service task setup complete ==="
echo "Tor Browser is running. Ready for agent to navigate to onion service and perform search."
