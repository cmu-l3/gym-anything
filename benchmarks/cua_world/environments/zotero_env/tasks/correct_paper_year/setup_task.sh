#!/bin/bash
# Setup for correct_paper_year task
# Seeds classic papers with deliberately wrong years for Einstein and Shannon

echo "=== Setting up correct_paper_year task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed classic papers with corrupted years ──────────────────────────────
echo "Seeding 10 classic papers with deliberate year errors..."
python3 /workspace/scripts/seed_library.py --mode classic_with_errors > /tmp/seed_ids.json 2>/tmp/seed_stderr.txt
SEED_EXIT=$?
cat /tmp/seed_stderr.txt
if [ $SEED_EXIT -ne 0 ]; then
    echo "ERROR: seeding failed"
    exit 1
fi

# Verify the errors were applied
EINSTEIN_YEAR=$(sqlite3 "$DB" "SELECT v.value FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID JOIN itemData dt ON i.itemID=dt.itemID JOIN itemDataValues vt ON dt.valueID=vt.valueID WHERE dt.fieldID=1 AND vt.value='On the Electrodynamics of Moving Bodies' AND d.fieldID=6" 2>/dev/null)
SHANNON_YEAR=$(sqlite3 "$DB" "SELECT v.value FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID JOIN itemData dt ON i.itemID=dt.itemID JOIN itemDataValues vt ON dt.valueID=vt.valueID WHERE dt.fieldID=1 AND vt.value='A Mathematical Theory of Communication' AND d.fieldID=6" 2>/dev/null)

echo "Einstein year (should be 1906): $EINSTEIN_YEAR"
echo "Shannon year (should be 1950): $SHANNON_YEAR"

# Sanity check
if [ "$EINSTEIN_YEAR" != "1906" ]; then
    echo "WARNING: Einstein year was not set to 1906 (got: $EINSTEIN_YEAR)"
fi
if [ "$SHANNON_YEAR" != "1950" ]; then
    echo "WARNING: Shannon year was not set to 1950 (got: $SHANNON_YEAR)"
fi

# ── 3. Baseline ──────────────────────────────────────────────────────────────
INITIAL_ITEM_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,28) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "0")
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count
echo "$EINSTEIN_YEAR" > /tmp/initial_einstein_year
echo "$SHANNON_YEAR" > /tmp/initial_shannon_year
date +%s > /tmp/task_start_timestamp

echo "Initial items: $INITIAL_ITEM_COUNT"

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

echo "=== Setup Complete: correct_paper_year ==="
echo "Einstein shows 1906 (should be 1905), Shannon shows 1950 (should be 1948)"
