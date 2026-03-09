#!/bin/bash
echo "=== Setting up attach_web_link_to_case task ==="
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
# We specifically need Gideon v. Wainwright
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "Current item count: $ITEM_COUNT"

if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse, loading legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded" || echo "Warning: Reference injection had issues"
    sleep 1
fi

# Ensure specific target case exists, if not, inject it explicitly (fallback)
# Using python one-liner to check existence of Gideon
HAS_GIDEON=$(python3 -c "
import sqlite3
conn = sqlite3.connect('$JURISM_DB')
c = conn.cursor()
c.execute(\"SELECT COUNT(*) FROM itemDataValues WHERE value LIKE '%Gideon%Wainwright%'\")
print(c.fetchone()[0])
conn.close()
" 2>/dev/null || echo "0")

if [ "$HAS_GIDEON" -eq "0" ]; then
    echo "Gideon case not found, injecting..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null
fi

# CLEANUP: Remove any existing attachments on Gideon v. Wainwright to ensure clean state
# 1. Get Gideon Item ID
GIDEON_ID=$(sqlite3 "$JURISM_DB" "SELECT items.itemID FROM items JOIN itemData ON items.itemID=itemData.itemID JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE fieldID=58 AND LOWER(value) LIKE '%gideon%wainwright%' LIMIT 1" 2>/dev/null || echo "")

if [ -n "$GIDEON_ID" ]; then
    echo "Cleaning up attachments for Gideon (ID: $GIDEON_ID)..."
    # Delete itemAttachments rows where parentItemID matches
    sqlite3 "$JURISM_DB" "DELETE FROM itemAttachments WHERE parentItemID=$GIDEON_ID"
    # Note: In a full cleanup we'd delete the child items from 'items' table too,
    # but strictly removing the attachment link is sufficient to reset the UI state for the user.
    # Let's try to do it properly:
    sqlite3 "$JURISM_DB" "DELETE FROM items WHERE itemID IN (SELECT itemID FROM itemAttachments WHERE parentItemID=$GIDEON_ID)"
    echo "Cleanup complete."
fi

# Record start timestamp
date +%s > /tmp/task_start_timestamp

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
DISPLAY=:1 import -window root /tmp/attach_task_start.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/attach_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="