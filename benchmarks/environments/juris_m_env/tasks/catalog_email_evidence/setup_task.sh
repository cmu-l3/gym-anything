#!/bin/bash
echo "=== Setting up catalog_email_evidence task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Record start timestamp
date +%s > /tmp/task_start_timestamp

# Clean up any existing items with the specific subject to ensure a clean test
# Subject: "Resignation implications"
echo "Cleaning up potential pre-existing task items..."
python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    # Find items with the specific title/subject
    c.execute('''
        SELECT DISTINCT itemData.itemID 
        FROM itemData 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE itemDataValues.value = 'Resignation implications'
    ''')
    rows = c.fetchall()
    for row in rows:
        item_id = row[0]
        print(f'Removing pre-existing item {item_id}')
        c.execute('DELETE FROM itemData WHERE itemID=?', (item_id,))
        c.execute('DELETE FROM itemCreators WHERE itemID=?', (item_id,))
        c.execute('DELETE FROM collectionItems WHERE itemID=?', (item_id,))
        c.execute('DELETE FROM items WHERE itemID=?', (item_id,))
    conn.commit()
    conn.close()
except Exception as e:
    print(f'Error during cleanup: {e}')
"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and dismiss alerts
wait_and_dismiss_jurism_alerts 45

# Maximize window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="