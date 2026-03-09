#!/bin/bash
echo "=== Setting up tag_short_papers task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library
echo "Seeding library..."
# Using 'all' mode to get a mix of papers (Classic + ML)
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_output.txt 2>/dev/null

# 3. Clean up any existing 'short-read' tags to ensure fresh start
if [ -f "$DB" ]; then
    echo "Cleaning existing tags..."
    sqlite3 "$DB" "DELETE FROM itemTags WHERE tagID IN (SELECT tagID FROM tags WHERE name='short-read');"
    sqlite3 "$DB" "DELETE FROM tags WHERE name='short-read';"
fi

# 4. Record task start time
date +%s > /tmp/task_start_time.txt
# Record initial modification times of items to detect changes
sqlite3 "$DB" "SELECT itemID, dateModified FROM items" > /tmp/initial_item_dates.txt

# 5. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# Wait for Zotero window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Zotero window found"
        break
    fi
    sleep 1
done
sleep 5

# Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 6. Take setup screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="