#!/bin/bash
echo "=== Setting up create_standalone_note task ==="
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

# 1. Clean up existing notes to ensure clean state
# 2. Ensure references exist for context (though note is standalone, library shouldn't be empty)
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Delete all notes (itemTypeID 1 is attachment, 31 is annotation? Zotero schema varies slightly but notes are typically distinct)
    # Safest: Delete from itemNotes and corresponding items
    cursor.execute('SELECT itemID FROM itemNotes')
    note_ids = [row[0] for row in cursor.fetchall()]
    
    if note_ids:
        placeholders = ','.join('?' for _ in note_ids)
        cursor.execute(f'DELETE FROM itemNotes WHERE itemID IN ({placeholders})', note_ids)
        cursor.execute(f'DELETE FROM items WHERE itemID IN ({placeholders})', note_ids)
        print(f'Deleted {len(note_ids)} existing notes')
    
    # Clear full-text search index for notes to prevent phantom hits
    try:
        cursor.execute('DELETE FROM fulltextItemWords')
        cursor.execute('DELETE FROM fulltextItems')
        cursor.execute('DELETE FROM fulltextWords')
    except:
        pass
        
    conn.commit()
    conn.close()
except Exception as e:
    print(f'Error cleaning DB: {e}')
    sys.exit(1)
" || echo "Warning: DB cleanup encountered issues"

# Inject references if library is sparse (provides the context mentioned in description)
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,14)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse, injecting references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null
fi

# Record start time and initial state
date +%s > /tmp/task_start_timestamp
INITIAL_NOTES=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM itemNotes WHERE parentItemID IS NULL" 2>/dev/null || echo "0")
echo "$INITIAL_NOTES" > /tmp/initial_standalone_count

echo "Task setup: Initial standalone notes: $INITIAL_NOTES"

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and handle alerts
wait_and_dismiss_jurism_alerts 45

# Maximize
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="