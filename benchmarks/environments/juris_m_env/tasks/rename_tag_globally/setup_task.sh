#!/bin/bash
set -e
echo "=== Setting up task: Rename Tag Globally ==="

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Find Jurism database
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Try to start Jurism once to initialize DB if it's missing
    ensure_jurism_running
    sleep 10
    pkill -f jurism
    sleep 2
    DB_PATH=$(get_jurism_db)
fi

if [ -z "$DB_PATH" ]; then
    echo "FATAL: Database still not found."
    exit 1
fi
echo "Using database: $DB_PATH"

# Stop Jurism to allow DB access without locking issues
echo "Stopping Jurism for database preparation..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject references if library is empty
ITEM_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library sparse, injecting references..."
    python3 /workspace/utils/inject_references.py "$DB_PATH"
fi

# ------------------------------------------------------------------
# SETUP TAGS AND ITEM ASSOCIATIONS
# ------------------------------------------------------------------

# Clean up any existing tags to ensure known state
python3 -c "
import sqlite3
import sys

db_path = '$DB_PATH'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Delete existing tags to start fresh
c.execute('DELETE FROM itemTags')
c.execute('DELETE FROM tags')

# Insert our target tags
tags = ['Equal Protection', 'Constitutional Law', 'Due Process']
tag_ids = {}
for t in tags:
    c.execute('INSERT INTO tags (name) VALUES (?)', (t,))
    tag_ids[t] = c.lastrowid

print(f'Created tags: {tag_ids}')

# Helper to find item ID by title string
def get_item_id(search_str):
    c.execute('''
        SELECT items.itemID FROM items 
        JOIN itemData ON items.itemID = itemData.itemID 
        JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
        WHERE fieldID IN (1, 58) AND value LIKE ? LIMIT 1
    ''', (f'%{search_str}%',))
    row = c.fetchone()
    return row[0] if row else None

# Assign 'Equal Protection' to specific cases
ep_cases = ['Brown v. Board', 'Obergefell', 'Gideon']
ep_item_ids = []
for case in ep_cases:
    iid = get_item_id(case)
    if iid:
        c.execute('INSERT OR IGNORE INTO itemTags (itemID, tagID, type) VALUES (?, ?, 0)', (iid, tag_ids['Equal Protection']))
        ep_item_ids.append(iid)
        print(f'Tagged {case} (ID {iid}) with Equal Protection')

# Assign 'Constitutional Law' to more cases (noise)
cl_cases = ['Brown', 'Obergefell', 'Gideon', 'Miranda', 'Tinker', 'New York Times']
for case in cl_cases:
    iid = get_item_id(case)
    if iid:
        c.execute('INSERT OR IGNORE INTO itemTags (itemID, tagID, type) VALUES (?, ?, 0)', (iid, tag_ids['Constitutional Law']))

# Assign 'Due Process'
dp_cases = ['Miranda', 'Gideon']
for case in dp_cases:
    iid = get_item_id(case)
    if iid:
        c.execute('INSERT OR IGNORE INTO itemTags (itemID, tagID, type) VALUES (?, ?, 0)', (iid, tag_ids['Due Process']))

conn.commit()
conn.close()

# Save the list of Equal Protection item IDs for verification later
with open('/tmp/initial_ep_item_ids.txt', 'w') as f:
    for iid in ep_item_ids:
        f.write(f'{iid}\n')
"

echo "Database preparation complete."
echo "Initial tagged items saved to /tmp/initial_ep_item_ids.txt"

# Remove integrity check flag to prevent "Database Upgrade" or "Integrity Check" dialogs on startup
# which might happen after external DB manipulation
sqlite3 "$DB_PATH" "DELETE FROM settings WHERE setting='db' AND key='integrityCheck'" 2>/dev/null || true
rm -f "${DB_PATH}-journal" 2>/dev/null || true

# ------------------------------------------------------------------
# START JURISM
# ------------------------------------------------------------------
echo "Starting Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'

# Wait for window and dismiss alerts
wait_and_dismiss_jurism_alerts 60

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Select the library root to ensure tags are visible
# (Clicking near top left - rough coordinate)
# DISPLAY=:1 xdotool mousemove 50 150 click 1 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="