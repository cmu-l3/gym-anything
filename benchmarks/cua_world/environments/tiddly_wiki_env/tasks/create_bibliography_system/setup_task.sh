#!/bin/bash
set -e
echo "=== Setting up Bibliography System task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count.txt
echo "Initial user tiddler count: $INITIAL_COUNT"

# Ensure TiddlyWiki server is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "Starting TiddlyWiki server..."
    su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
    for i in $(seq 1 30); do
        if curl -s http://localhost:8080/ > /dev/null 2>&1; then
            echo "TiddlyWiki server started"
            break
        fi
        sleep 1
    done
fi

# Ensure Firefox is running and pointing to TiddlyWiki
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|tiddly"; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|tiddly"; then
            echo "Firefox window detected"
            break
        fi
        sleep 1
    done
    sleep 3
fi

# Maximize and focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    echo "Firefox maximized and focused"
fi

# Wait for page to fully load
sleep 3

# Dismiss any popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="
echo "TiddlyWiki is running at http://localhost:8080/"