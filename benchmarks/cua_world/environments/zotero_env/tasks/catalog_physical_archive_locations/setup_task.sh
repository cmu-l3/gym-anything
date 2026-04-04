#!/bin/bash
# Setup for catalog_physical_archive_locations task
# Seeds classic papers into Zotero library

echo "=== Setting up catalog_physical_archive_locations task ==="

DB="/home/ga/Zotero/zotero.sqlite"
SEED_SCRIPT="/workspace/scripts/seed_library.py"

# ── 1. Stop Zotero ───────────────────────────────────────────────────────────
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# ── 2. Seed Library ──────────────────────────────────────────────────────────
# Use 'classic' mode which contains Einstein, Turing, Shannon
echo "Seeding library with classic papers..."
if [ -f "$SEED_SCRIPT" ]; then
    python3 "$SEED_SCRIPT" --mode classic > /tmp/seed_output.txt 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: seed_library.py failed"
        cat /tmp/seed_output.txt
        exit 1
    fi
else
    echo "ERROR: Seed script not found at $SEED_SCRIPT"
    exit 1
fi

# ── 3. Clear any existing Call Numbers (Sanity Check) ────────────────────────
# This ensures we start from a clean state even if the seed script changes
echo "Clearing any existing call numbers..."
sqlite3 "$DB" <<EOF
DELETE FROM itemData 
WHERE fieldID = (SELECT fieldID FROM fields WHERE fieldName='callNumber');
EOF

# ── 4. Record Initial State ──────────────────────────────────────────────────
INITIAL_ITEM_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,28) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "0")
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count

# Record timestamp for anti-gaming (edits must happen after this)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

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
sleep 5

# Activate and maximize
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# ── 6. Initial Screenshot ────────────────────────────────────────────────────
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete: catalog_physical_archive_locations ==="