#!/bin/bash
echo "=== Setting up create_standalone_research_notes task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to safely modify/check DB
pkill -9 -f zotero 2>/dev/null || true
sleep 2

# 2. Seed library with standard papers
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Clean up any existing artifacts (ensure clean slate)
# Remove "Dissertation Notes" collection if it exists
sqlite3 "$DB" "DELETE FROM collections WHERE collectionName='Dissertation Notes';" 2>/dev/null
# Remove any existing standalone notes (itemTypeID=28 and parentItemID IS NULL)
# Note: In a real scenario we might be more selective, but for task setup we want a clean state for these specific items
sqlite3 "$DB" "DELETE FROM items WHERE itemID IN (SELECT itemID FROM itemNotes WHERE parentItemID IS NULL);" 2>/dev/null
sqlite3 "$DB" "DELETE FROM itemNotes WHERE parentItemID IS NULL;" 2>/dev/null

# 4. Record initial state
INITIAL_COLL_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM collections" 2>/dev/null || echo "0")
INITIAL_NOTE_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM itemNotes WHERE parentItemID IS NULL" 2>/dev/null || echo "0")
echo "$INITIAL_COLL_COUNT" > /tmp/initial_collection_count
echo "$INITIAL_NOTE_COUNT" > /tmp/initial_standalone_note_count
date +%s > /tmp/task_start_time

# 5. Start Zotero
echo "Starting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# 6. Wait for window and maximize
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="