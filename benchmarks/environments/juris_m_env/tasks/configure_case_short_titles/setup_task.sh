#!/bin/bash
echo "=== Setting up configure_case_short_titles task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access (DB is locked while Jurism runs)
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Inject references if library is sparse
# This script (utils/inject_references.py) includes Brown, Miranda, and Obergefell by default
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse ($ITEM_COUNT items), injecting references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded" || echo "Warning: injection had issues"
else
    echo "Library has $ITEM_COUNT items."
fi

# 2. CLEAR Short Titles for the target cases to ensure a clean start state
# FieldID 3 is shortTitle. FieldID 58 is caseName.
python3 -c "
import sqlite3
import time

db_path = '$JURISM_DB'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

target_cases = ['Brown v. Board of Education', 'Miranda v. Arizona', 'Obergefell v. Hodges']

print('Clearing Short Titles for target cases...')

for case_name in target_cases:
    # Find itemID
    cursor.execute('''
        SELECT items.itemID 
        FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE fieldID=58 AND value LIKE ?
    ''', (f'%{case_name}%',))
    
    rows = cursor.fetchall()
    for row in rows:
        item_id = row[0]
        # Delete existing shortTitle (fieldID=3) for this item
        cursor.execute('DELETE FROM itemData WHERE itemID=? AND fieldID=3', (item_id,))
        # Update modification time to before task start (so we can detect new edits)
        old_date = '2020-01-01 00:00:00'
        cursor.execute('UPDATE items SET dateModified=?, clientDateModified=? WHERE itemID=?', (old_date, old_date, item_id))
        print(f'  Cleared shortTitle for item {item_id} ({case_name})')

conn.commit()
conn.close()
" 2>&1 || echo "Warning: Python DB setup failed"

# Remove any lingering journal file
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="