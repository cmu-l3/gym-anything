#!/bin/bash
set -e
echo "=== Setting up manually_add_references task ==="

# Record task start time (for anti-gaming verification)
# We use Python to get a precise timestamp compatible with SQLite checks if needed,
# though standard unix epoch is usually fine.
date +%s > /tmp/task_start_time.txt

# Ensure Zotero directory exists
mkdir -p /home/ga/Zotero

# Zotero DB path
DB_PATH="/home/ga/Zotero/zotero.sqlite"

# Check/Seed initial library
# We use the seed script to ensure there's a base state (classic papers)
# preventing an empty library which might confuse the agent or verifier delta checks
if [ -f "/workspace/scripts/seed_library.py" ]; then
    echo "Seeding library with classic papers..."
    python3 /workspace/scripts/seed_library.py --mode classic > /dev/null 2>&1 || true
fi

# Record initial item count
if [ -f "$DB_PATH" ]; then
    INITIAL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14, 28) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "0")
else
    INITIAL_COUNT="0"
fi
echo "$INITIAL_COUNT" > /tmp/initial_item_count.txt
echo "Initial item count: $INITIAL_COUNT"

# Ensure Zotero is running
if ! pgrep -f "zotero" > /dev/null; then
    echo "Starting Zotero..."
    # Launch logic borrowed from env setup
    sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'
    sleep 10
fi

# Wait for window
echo "Waiting for Zotero window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Dismiss any startup dialogs (Esc key)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="