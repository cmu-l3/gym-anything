#!/bin/bash
echo "=== Setting up import_legal_references task ==="
source /workspace/scripts/task_utils.sh

# Copy the RIS file to Documents folder
mkdir -p /home/ga/Documents
cp /workspace/assets/sample_data/supreme_court_cases.ris /home/ga/Documents/
chown ga:ga /home/ga/Documents/supreme_court_cases.ris
echo "RIS file copied to /home/ga/Documents/supreme_court_cases.ris"

# Find Jurism database
JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then
        JURISM_DB="$db_candidate"
        break
    fi
done

# Stop Jurism to allow DB access (DB is locked while Jurism runs)
echo "Stopping Jurism for DB access..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Clear existing user items so the library starts empty for the import task
# Also clear tags, integrityCheck flag, and journal file to prevent Jurism rendering errors
if [ -f "$JURISM_DB" ]; then
    python3 -c "
import sqlite3
conn = sqlite3.connect('$JURISM_DB')
c = conn.cursor()
# Delete user-created items (exclude system types: 1=attachment, 3=note, 31=annotation)
c.execute('DELETE FROM itemCreators WHERE itemID IN (SELECT itemID FROM items WHERE itemTypeID NOT IN (1,3,31))')
c.execute('DELETE FROM itemData WHERE itemID IN (SELECT itemID FROM items WHERE itemTypeID NOT IN (1,3,31))')
c.execute('DELETE FROM collectionItems WHERE itemID IN (SELECT itemID FROM items WHERE itemTypeID NOT IN (1,3,31))')
c.execute('DELETE FROM items WHERE itemTypeID NOT IN (1,3,31)')
# Clear tags from previous imports (KW tags trigger Jurism integrityCheck rendering bug)
c.execute('DELETE FROM itemTags')
c.execute('DELETE FROM tags')
# Remove integrityCheck flag that can persist from previous imports
c.execute(\"DELETE FROM settings WHERE setting='db' AND key='integrityCheck'\")
conn.commit()
c.execute('SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)')
print(f'Items after clear: {c.fetchone()[0]}')
conn.close()
" 2>&1 || echo "Warning: DB clear had issues"
    # Remove any lingering journal file from previous Jurism operations
    rm -f "${JURISM_DB}-journal" 2>/dev/null || true
    INITIAL_COUNT=0
    echo "$INITIAL_COUNT" > /tmp/initial_item_count
    date +%s > /tmp/task_start_timestamp
    echo "Library cleared, initial item count: $INITIAL_COUNT"
else
    echo "0" > /tmp/initial_item_count
    date +%s > /tmp/task_start_timestamp
    echo "Jurism database not found"
fi

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
DISPLAY=:1 import -window root /tmp/import_task_start.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/import_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "File ready at: /home/ga/Documents/supreme_court_cases.ris"
echo "Library starts with: $(cat /tmp/initial_item_count) items"
