#!/bin/bash
echo "=== Setting up create_law_collection task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then
        JURISM_DB="$db_candidate"
        break
    fi
done

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access (DB is locked while Jurism runs)
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Check item count and inject references if library is sparse
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "Current item count: $ITEM_COUNT"

if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse, loading legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded" || echo "Warning: Reference injection had issues"
    sleep 1
fi

# Remove any pre-existing collections so task starts clean
sqlite3 "$JURISM_DB" "DELETE FROM collectionItems; DELETE FROM collections;" 2>/dev/null || echo "Warning: Could not clear collections"

# Record initial collection count (should be 0 after clear) and task start timestamp
INITIAL_COLL=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM collections" 2>/dev/null || echo "0")
echo "$INITIAL_COLL" > /tmp/initial_collection_count
date +%s > /tmp/task_start_timestamp
echo "Initial collection count: $INITIAL_COLL"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism to load and dismiss any in-app alert dialogs
wait_and_dismiss_jurism_alerts 45

# Maximize and focus Jurism window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take screenshot to verify state
DISPLAY=:1 import -window root /tmp/collection_task_start.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/collection_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="
FINAL_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "locked")
echo "Library has $FINAL_COUNT items"
