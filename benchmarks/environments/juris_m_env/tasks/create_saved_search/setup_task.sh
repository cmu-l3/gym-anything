#!/bin/bash
echo "=== Setting up create_saved_search task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    # Fallback search if utils fail
    JURISM_DB=$(find /home/ga -name "jurism.sqlite" 2>/dev/null | head -1)
fi

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism for setup..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. CLEANUP: Remove existing saved searches and specific test items to ensure clean state
echo "Cleaning database..."
python3 -c "
import sqlite3
import sys

try:
    conn = sqlite3.connect('$JURISM_DB')
    c = conn.cursor()
    
    # Remove all saved searches
    c.execute('DELETE FROM savedSearchConditions')
    c.execute('DELETE FROM savedSearches')
    
    # Remove existing items to ensure clean injection (keep system items)
    # This prevents duplicate injections if task is retried
    c.execute('DELETE FROM itemCreators WHERE itemID IN (SELECT itemID FROM items WHERE itemTypeID NOT IN (1,3,31))')
    c.execute('DELETE FROM itemData WHERE itemID IN (SELECT itemID FROM items WHERE itemTypeID NOT IN (1,3,31))')
    c.execute('DELETE FROM collectionItems')
    c.execute('DELETE FROM items WHERE itemTypeID NOT IN (1,3,31)')
    
    conn.commit()
    print('Database cleaned.')
    conn.close()
except Exception as e:
    print(f'Error cleaning DB: {e}')
    sys.exit(1)
"

# 2. INJECT DATA: Load the 10 specific legal references
echo "Injecting legal references..."
# We use the existing utility but modify it or use it directly if it supports our specific list.
# Since the utils/inject_references.py in the environment has the exact list we need 
# (Brown, Marbury, Miranda, etc.), we can run it directly.
python3 /workspace/utils/inject_references.py "$JURISM_DB"

# 3. RECORD INITIAL STATE
INITIAL_SEARCH_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM savedSearches" 2>/dev/null || echo "0")
echo "$INITIAL_SEARCH_COUNT" > /tmp/initial_saved_search_count.txt
echo "Initial saved searches: $INITIAL_SEARCH_COUNT"

# 4. LAUNCH JURISM
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
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="