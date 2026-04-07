#!/bin/bash
# setup_task.sh for osint_evidence_archival task
# Prepares Tor Browser and ensures a clean evidence directory

set -e
echo "=== Setting up osint_evidence_archival task ==="

TASK_NAME="osint_evidence_archival"
EVIDENCE_DIR="/home/ga/Documents/CaseEvidence"

# 1. Kill any existing Tor Browser instances
echo "Killing any existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# 2. Set up evidence directory
echo "Preparing evidence directory at $EVIDENCE_DIR..."
sudo -u ga mkdir -p "$EVIDENCE_DIR"
# Ensure it is empty (clean state)
rm -rf "${EVIDENCE_DIR:?}"/* 2>/dev/null || true
chown -R ga:ga "$EVIDENCE_DIR"

# 3. Find Tor Browser profile and clear history
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

if [ -n "$PROFILE_DIR" ]; then
    PLACES_DB="$PROFILE_DIR/places.sqlite"
    if [ -f "$PLACES_DB" ]; then
        echo "Clearing browsing history to ensure clean task state..."
        rm -f "$PLACES_DB" 2>/dev/null || true
        rm -f "${PLACES_DB}-shm" 2>/dev/null || true
        rm -f "${PLACES_DB}-wal" 2>/dev/null || true
    fi
fi

# 4. Record task start timestamp for anti-gaming checks
# Ensure timestamp is recorded right before agent gains control
date +%s > "/tmp/${TASK_NAME}_start_ts"
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# 5. Find and launch Tor Browser
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

# 6. Wait for process and window
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

# 7. Wait for Tor connection
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
    echo "WARNING: Tor did not connect within ${TIMEOUT}s. Agent may need to click Connect."
fi

# Let UI settle
sleep 5

# Focus and maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 8. Take initial screenshot
DISPLAY=:1 import -window root "/tmp/${TASK_NAME}_start.png" 2>/dev/null || \
    DISPLAY=:1 scrot "/tmp/${TASK_NAME}_start.png" 2>/dev/null || true

echo "=== osint_evidence_archival task setup complete ==="