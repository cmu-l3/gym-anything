#!/bin/bash
# Setup for tag_and_search_pipeline task
# Seeds 20 systems papers in a "Reading Queue" collection;
# 6 are pre-tagged "priority" (4 pre-2010, 2 post-2010).

echo "=== Setting up tag_and_search_pipeline task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero so we can seed the DB ────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed papers ───────────────────────────────────────────────────────────
echo "Seeding 20 systems papers with 6 pre-tagged priority..."
SEED_OUTPUT=$(python3 /workspace/scripts/seed_library.py --mode triage_pipeline 2>/tmp/seed_stderr.txt)
SEED_EXIT=$?
cat /tmp/seed_stderr.txt
if [ $SEED_EXIT -ne 0 ]; then
    echo "ERROR: seed_library.py failed"
    exit 1
fi
echo "Seed complete"

# ── 3. Record baseline state ─────────────────────────────────────────────────
INITIAL_ITEM_COUNT=$(sqlite3 "$DB" \
    "SELECT COUNT(*) FROM items WHERE itemTypeID=22 AND itemID NOT IN (SELECT itemID FROM deletedItems)" \
    2>/dev/null || echo "0")
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count

# Count priority-tagged items
PRIORITY_COUNT=$(sqlite3 "$DB" \
    "SELECT COUNT(DISTINCT it.itemID) FROM itemTags it JOIN tags t ON it.tagID=t.tagID WHERE t.name='priority'" \
    2>/dev/null || echo "0")
echo "$PRIORITY_COUNT" > /tmp/initial_priority_count

# Verify 6 priority papers exist
if [ "$PRIORITY_COUNT" -ne 6 ]; then
    echo "WARNING: Expected 6 priority-tagged papers, found $PRIORITY_COUNT"
fi

date +%s > /tmp/task_start_timestamp

# ── 4. Restart Zotero ────────────────────────────────────────────────────────
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

# ── 5. Take screenshot ───────────────────────────────────────────────────────
DISPLAY=:1 import -window root /tmp/task_start_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true
echo "Screenshot saved"

echo "=== Setup Complete: tag_and_search_pipeline ==="
echo "Library has $INITIAL_ITEM_COUNT papers, $PRIORITY_COUNT priority-tagged"
