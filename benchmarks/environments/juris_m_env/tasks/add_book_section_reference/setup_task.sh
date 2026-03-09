#!/bin/bash
set -e
echo "=== Setting up add_book_section_reference task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    # If not found immediately, try to start Jurism once to initialize, then find it
    ensure_jurism_running
    JURISM_DB=$(get_jurism_db)
fi

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database even after starting app"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access (DB is locked while Jurism runs)
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Clean up specific target item if it exists (anti-collision)
# We remove any item containing "Natural Law: The Modern Tradition" in its title
python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    # Find items with the specific title
    c.execute('''
        SELECT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE itemDataValues.value LIKE '%Natural Law: The Modern Tradition%'
    ''')
    ids = [row[0] for row in c.fetchall()]
    
    if ids:
        print(f'Removing {len(ids)} existing target items...')
        for iid in ids:
            c.execute('DELETE FROM itemData WHERE itemID=?', (iid,))
            c.execute('DELETE FROM itemCreators WHERE itemID=?', (iid,))
            c.execute('DELETE FROM items WHERE itemID=?', (iid,))
        conn.commit()
    else:
        print('No existing target items found.')
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
"

# 2. Ensure library has some background items (so it's not empty)
# This uses the utility function which injects standard cases/articles
# only if the library is sparse.
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Loading background legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null || true
fi

# Remove journal file to prevent lock errors
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# 3. Relaunch Jurism
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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="