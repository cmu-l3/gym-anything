#!/bin/bash
# Setup for export_collection_bibtex task
# Seeds 8 ML papers + creates "ML References" collection with all 8 papers

echo "=== Setting up export_collection_bibtex task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Ensure Desktop directory exists ───────────────────────────────────────
sudo -u ga mkdir -p /home/ga/Desktop
# Remove any pre-existing output file
rm -f /home/ga/Desktop/ml_bibliography.bib

# ── 3. Seed papers + collection ──────────────────────────────────────────────
echo "Seeding ML papers and creating 'ML References' collection..."
python3 /workspace/scripts/seed_library.py --mode ml_with_collection > /tmp/seed_ids.json 2>/tmp/seed_stderr.txt
SEED_EXIT=$?
cat /tmp/seed_stderr.txt
if [ $SEED_EXIT -ne 0 ]; then
    echo "ERROR: seeding failed"
    exit 1
fi

# Verify collection was created
COLL_ID=$(sqlite3 "$DB" "SELECT collectionID FROM collections WHERE collectionName='ML References' AND libraryID=1" 2>/dev/null)
if [ -z "$COLL_ID" ]; then
    echo "ERROR: 'ML References' collection not found after seeding!"
    exit 1
fi
COLL_ITEM_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM collectionItems WHERE collectionID=$COLL_ID" 2>/dev/null || echo "0")
echo "Collection 'ML References' (ID=$COLL_ID) has $COLL_ITEM_COUNT items"

# ── 4. Baseline ──────────────────────────────────────────────────────────────
INITIAL_ITEM_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,28) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "0")
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count
echo "$COLL_ID" > /tmp/ml_references_collection_id
date +%s > /tmp/task_start_timestamp

# ── 5. Restart Zotero ────────────────────────────────────────────────────────
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

# ── 6. Screenshot ─────────────────────────────────────────────────────────────
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete: export_collection_bibtex ==="
echo "Library: $INITIAL_ITEM_COUNT items, collection 'ML References' with $COLL_ITEM_COUNT items"
