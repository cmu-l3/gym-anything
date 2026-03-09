#!/bin/bash
# Setup for add_reading_note task
# Seeds 18 papers into Zotero library, then restarts Zotero

echo "=== Setting up add_reading_note task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero so we can seed the DB ────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed papers into database ────────────────────────────────────────────
echo "Seeding library with 18 papers..."
SEED_OUTPUT=$(python3 /workspace/scripts/seed_library.py --mode all 2>/tmp/seed_stderr.txt)
SEED_EXIT=$?
cat /tmp/seed_stderr.txt
if [ $SEED_EXIT -ne 0 ]; then
    echo "ERROR: seed_library.py failed"
    cat /tmp/seed_stderr.txt
    exit 1
fi
echo "Seed output: $SEED_OUTPUT"

# ── 3. Record baseline state ─────────────────────────────────────────────────
INITIAL_ITEM_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,28) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "0")
INITIAL_NOTE_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM itemNotes" 2>/dev/null || echo "0")
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count
echo "$INITIAL_NOTE_COUNT" > /tmp/initial_note_count
echo "Initial items: $INITIAL_ITEM_COUNT, initial notes: $INITIAL_NOTE_COUNT"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# ── 4. Verify target paper exists ────────────────────────────────────────────
TARGET_ID=$(sqlite3 "$DB" "SELECT i.itemID FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=1 AND v.value='Attention Is All You Need'" 2>/dev/null)
if [ -z "$TARGET_ID" ]; then
    echo "ERROR: Target paper 'Attention Is All You Need' not found in DB!"
    exit 1
fi
echo "Target paper itemID: $TARGET_ID"
echo "$TARGET_ID" > /tmp/target_paper_id

# ── 5. Restart Zotero ────────────────────────────────────────────────────────
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# Wait for Zotero window
echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Zotero window found after ${i}s"
        break
    fi
    sleep 1
done

sleep 3

# Activate and maximize
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# ── 6. Take setup screenshot ─────────────────────────────────────────────────
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
echo "Screenshot saved"

echo "=== Setup Complete: add_reading_note ==="
echo "Library has $INITIAL_ITEM_COUNT papers. Target paper ID: $TARGET_ID"
