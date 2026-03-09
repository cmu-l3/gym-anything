#!/bin/bash
set -e
echo "=== Setting up Curate Warren Court Collection task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Get database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

echo "Using database: $DB_PATH"

# Ensure Jurism is closed to modify DB safely
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject the standard set of legal references
# This set includes the target Warren Court cases and distractors
python3 /workspace/utils/inject_references.py "$DB_PATH" all
echo "References injected."

# Remove the target collection if it already exists (idempotency)
# We use python for cleaner DB access
python3 -c "
import sqlite3
import sys

db_path = '$DB_PATH'
try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Find collection ID for 'Warren Court'
    cursor.execute('SELECT collectionID FROM collections WHERE collectionName = ?', ('Warren Court',))
    row = cursor.fetchone()
    
    if row:
        coll_id = row[0]
        print(f'Removing existing Warren Court collection (ID: {coll_id})')
        # Remove items from collection
        cursor.execute('DELETE FROM collectionItems WHERE collectionID = ?', (coll_id,))
        # Remove collection
        cursor.execute('DELETE FROM collections WHERE collectionID = ?', (coll_id,))
        conn.commit()
    else:
        print('No existing Warren Court collection found.')
        
    conn.close()
except Exception as e:
    print(f'Error cleaning DB: {e}')
"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism.log 2>&1 &'
sleep 5

# Handle alerts and maximize
wait_and_dismiss_jurism_alerts 45
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="