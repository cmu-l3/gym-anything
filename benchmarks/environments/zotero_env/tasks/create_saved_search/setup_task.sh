#!/bin/bash
# Setup for create_saved_search task
# Seeds all 18 papers for the agent to search through

echo "=== Setting up create_saved_search task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed all 18 papers ─────────────────────────────────────────────────────
echo "Seeding 18 papers..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_ids.json 2>/tmp/seed_stderr.txt
SEED_EXIT=$?
cat /tmp/seed_stderr.txt
if [ $SEED_EXIT -ne 0 ]; then
    echo "ERROR: seeding failed"
    exit 1
fi

# ── 3. Baseline ──────────────────────────────────────────────────────────────
INITIAL_ITEM_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,28) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "0")
INITIAL_SEARCH_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM savedSearches WHERE libraryID=1" 2>/dev/null || echo "0")
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count
echo "$INITIAL_SEARCH_COUNT" > /tmp/initial_search_count
date +%s > /tmp/task_start_timestamp

echo "Initial: $INITIAL_ITEM_COUNT items, $INITIAL_SEARCH_COUNT saved searches"

# Show papers and their years to confirm data looks right
echo "Papers by year range:"
sqlite3 "$DB" "SELECT v.value, vt.value FROM items i JOIN itemData d ON i.itemID=d.itemID AND d.fieldID=6 JOIN itemDataValues v ON d.valueID=v.valueID JOIN itemData dt ON i.itemID=dt.itemID AND dt.fieldID=1 JOIN itemDataValues vt ON dt.valueID=vt.valueID WHERE i.itemTypeID NOT IN (1,3,28) ORDER BY v.value" 2>/dev/null | head -20

# ── 4. Restart Zotero ────────────────────────────────────────────────────────
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "  Window found after ${i}s"
        break
    fi
    sleep 1
done
sleep 3
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# ── 5. Screenshot ─────────────────────────────────────────────────────────────
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete: create_saved_search ==="
