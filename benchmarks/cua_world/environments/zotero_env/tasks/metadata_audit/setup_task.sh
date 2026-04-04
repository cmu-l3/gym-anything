#!/bin/bash
# Setup for metadata_audit task
# Seeds 25 science papers with planted errors:
#   - 5 year errors (off by 10 years)
#   - 5 swapped author names
#   - 5 placeholder abstracts

echo "=== Setting up metadata_audit task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ────────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed papers ────────────────────────────────────────────────────────────
echo "Seeding 25 biology/medicine papers with planted errors..."
SEED_OUTPUT=$(python3 /workspace/scripts/seed_library.py --mode metadata_audit 2>/tmp/seed_stderr.txt)
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

# Count placeholder abstracts
PLACEHOLDER_COUNT=$(sqlite3 "$DB" \
    "SELECT COUNT(*) FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=2 AND v.value='Abstract not available'" \
    2>/dev/null || echo "0")
echo "$PLACEHOLDER_COUNT" > /tmp/initial_placeholder_count
echo "Initial placeholders: $PLACEHOLDER_COUNT"

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

echo "=== Setup Complete: metadata_audit ==="
echo "Library has $INITIAL_ITEM_COUNT papers with $PLACEHOLDER_COUNT placeholder abstracts"
