#!/bin/bash
echo "=== Setting up catalog_legal_cases task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
# Also save formatted date for potential SQL comparisons if needed
date -u +"%Y-%m-%d %H:%M:%S" > /tmp/task_start_iso.txt

# Ensure Zotero is running and accessible
# Check if window exists
if ! DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
    echo "Starting Zotero..."
    # Kill any zombie processes
    pkill -9 -f zotero 2>/dev/null || true
    
    # Start Zotero
    sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'
    
    # Wait for window
    echo "Waiting for Zotero window..."
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
            echo "Window detected"
            break
        fi
        sleep 1
    done
fi

# Ensure window is maximized and focused
echo "Configuring window..."
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Record initial item count for debugging
ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"
if [ -f "$ZOTERO_DB" ]; then
    INITIAL_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14)" 2>/dev/null || echo "0")
    echo "$INITIAL_COUNT" > /tmp/initial_item_count.txt
    echo "Initial item count: $INITIAL_COUNT"
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="