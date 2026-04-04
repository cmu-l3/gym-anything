#!/bin/bash
set -e
echo "=== Setting up add_patent_reference task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Try to find it manually if utils fail
    for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
        if [ -f "$db_candidate" ]; then
            JURISM_DB="$db_candidate"
            break
        fi
    done
fi

if [ -z "$JURISM_DB" ]; then
    echo "CRITICAL: Jurism database not found. Creating directory structure."
    mkdir -p /home/ga/Jurism
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Ensure library has some items (inject if sparse)
if [ -f "$JURISM_DB" ]; then
    ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
    if [ "$ITEM_COUNT" -lt 5 ]; then
        echo "Library sparse ($ITEM_COUNT items), injecting references..."
        python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null || echo "Injection warning"
    fi
    
    # CLEANUP: Remove any existing patent matching our target to ensure clean state
    # We look for items with title containing "unlocking a device"
    python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    # Find itemIDs with title containing 'unlocking a device'
    c.execute('''
        SELECT DISTINCT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID
        WHERE itemDataValues.value LIKE '%unlocking a device%'
    ''')
    ids = [row[0] for row in c.fetchall()]
    
    for iid in ids:
        print(f'Removing pre-existing item {iid}...')
        c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
        c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
        c.execute('DELETE FROM collectionItems WHERE itemID=?', (iid,))
        c.execute('DELETE FROM items WHERE itemID=?', (iid,))
    
    conn.commit()
    conn.close()
except Exception as e:
    print(f'Cleanup error: {e}')
"
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_launch.log 2>&1 &'
sleep 5

# Wait for alerts
wait_and_dismiss_jurism_alerts 45

# Maximize
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="