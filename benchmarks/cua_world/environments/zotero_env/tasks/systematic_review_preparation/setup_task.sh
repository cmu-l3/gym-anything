#!/bin/bash
# Setup for systematic_review_preparation task
# Seeds 25 computational neuroscience papers:
#   - 4 pre-2000 papers (to be trashed by agent)
#   - 4 with placeholder abstracts (to be flagged by agent)
#   - 3 duplicate pairs with metadata variations (to be merged by agent)
#   - 2 papers with abbreviated venue names (to be fixed by agent)
#   - 9 clean papers

echo "=== Setting up systematic_review_preparation task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero so we can seed the DB ──────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Delete stale outputs BEFORE recording timestamp ────────────────────
rm -f /home/ga/Desktop/included_studies.bib
rm -f /tmp/systematic_review_preparation_result.json
rm -f /tmp/task_start_screenshot.png
rm -f /tmp/task_end_screenshot.png

# ── 3. Seed papers ────────────────────────────────────────────────────────
echo "Seeding 25 computational neuroscience papers..."
SEED_OUTPUT=$(python3 /workspace/scripts/seed_library.py --mode systematic_review 2>/tmp/seed_stderr.txt)
SEED_EXIT=$?
cat /tmp/seed_stderr.txt
if [ $SEED_EXIT -ne 0 ]; then
    echo "ERROR: seed_library.py failed"
    exit 1
fi
echo "Seed complete"

# ── 4. Record baseline state ──────────────────────────────────────────────
INITIAL_ITEM_COUNT=$(sqlite3 "$DB" \
    "SELECT COUNT(*) FROM items WHERE itemTypeID=22 AND itemID NOT IN (SELECT itemID FROM deletedItems)" \
    2>/dev/null || echo "0")
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count

PLACEHOLDER_COUNT=$(sqlite3 "$DB" \
    "SELECT COUNT(*) FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=2 AND v.value='Abstract not available'" \
    2>/dev/null || echo "0")
echo "$PLACEHOLDER_COUNT" > /tmp/initial_placeholder_count

echo "Initial items: $INITIAL_ITEM_COUNT (expect 25), placeholder abstracts: $PLACEHOLDER_COUNT (expect 4)"
date +%s > /tmp/task_start_timestamp

# ── 5. Restart Zotero ─────────────────────────────────────────────────────
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

# ── 6. Take screenshot ────────────────────────────────────────────────────
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
echo "Screenshot saved"

echo "=== Setup Complete: systematic_review_preparation ==="
echo "Library has $INITIAL_ITEM_COUNT papers, $PLACEHOLDER_COUNT with placeholder abstracts"
