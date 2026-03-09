#!/bin/bash
# Setup for citation_qa_export task
# Seeds 20 CS theory papers all tagged "cite-in-paper":
#   - 11 clean, 3 with empty publication title, 6 from 3 duplicate pairs

echo "=== Setting up citation_qa_export task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ────────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed papers ────────────────────────────────────────────────────────────
echo "Seeding 20 CS theory papers tagged 'cite-in-paper'..."
SEED_OUTPUT=$(python3 /workspace/scripts/seed_library.py --mode citation_qa 2>/tmp/seed_stderr.txt)
SEED_EXIT=$?
cat /tmp/seed_stderr.txt
if [ $SEED_EXIT -ne 0 ]; then
    echo "ERROR: seed_library.py failed"
    exit 1
fi

# ── 3. Record baseline ────────────────────────────────────────────────────────
INITIAL_ITEM_COUNT=$(sqlite3 "$DB" \
    "SELECT COUNT(*) FROM items WHERE itemTypeID=22 AND itemID NOT IN (SELECT itemID FROM deletedItems)" \
    2>/dev/null || echo "0")
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count

CITE_TAGGED=$(sqlite3 "$DB" \
    "SELECT COUNT(DISTINCT it.itemID) FROM itemTags it JOIN tags t ON it.tagID=t.tagID WHERE t.name='cite-in-paper'" \
    2>/dev/null || echo "0")
echo "$CITE_TAGGED" > /tmp/initial_cite_tagged_count

EMPTY_JOURNAL=$(sqlite3 "$DB" \
    "SELECT COUNT(*) FROM items WHERE itemTypeID=22 AND itemID NOT IN (SELECT itemID FROM itemData WHERE fieldID=38)" \
    2>/dev/null || echo "0")
echo "$EMPTY_JOURNAL" > /tmp/initial_empty_journal_count

echo "Initial cite-in-paper items: $CITE_TAGGED, empty journal: $EMPTY_JOURNAL"
date +%s > /tmp/task_start_timestamp

# ── 4. Restart Zotero ─────────────────────────────────────────────────────────
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

echo "Waiting for Zotero window..."
for i in $(seq 1 45); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Zotero window found after ${i}s"
        break
    fi
    sleep 1
done
sleep 3

DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# ── 5. Take screenshot ────────────────────────────────────────────────────────
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
echo "Screenshot saved"

echo "=== Setup Complete: citation_qa_export ==="
echo "$CITE_TAGGED papers tagged 'cite-in-paper'; $EMPTY_JOURNAL with empty journal"
