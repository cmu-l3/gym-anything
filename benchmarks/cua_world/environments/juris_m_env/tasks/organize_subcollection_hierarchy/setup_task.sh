#!/bin/bash
echo "=== Setting up organize_subcollection_hierarchy task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    # Try to find it in standard locations if helper fails
    for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
        if [ -f "$db_candidate" ]; then
            JURISM_DB="$db_candidate"
            break
        fi
    done
fi

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Clear existing collections to ensure clean state
# 2. Ensure references are loaded
python3 -c "
import sqlite3
import sys
import os

db_path = '$JURISM_DB'
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Clear collections
print('Clearing existing collections...')
c.execute('DELETE FROM collectionItems')
c.execute('DELETE FROM collections')

# Check item count
c.execute('SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)')
count = c.fetchone()[0]
print(f'Current item count: {count}')

conn.commit()
conn.close()
"

# Inject references if needed (using the environment's utility)
# We force injection to ensure all 10 specific items needed for the task are present
echo "Injecting required legal references..."
python3 /workspace/utils/inject_references.py "$JURISM_DB" > /tmp/injection.log 2>&1 || echo "Injection script returned error (might be duplicates)"

# Record initial state
sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM collections" > /tmp/initial_collection_count
echo "Initial collection count: $(cat /tmp/initial_collection_count)"

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
sleep 1

# Take initial screenshot
take_screenshot /tmp/hierarchy_task_start.png

echo "=== Task setup complete ==="