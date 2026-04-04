#!/bin/bash
echo "=== Setting up standardize_journal_abbreviations task ==="
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then
        JURISM_DB="$db_candidate"
        break
    fi
done

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi

echo "Using database: $JURISM_DB"

# Stop Jurism to allow DB access
echo "Stopping Jurism for DB operations..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Ensure library has the required references
# We check for one of the specific target items
ITEM_CHECK=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM itemDataValues WHERE value LIKE '%Path of the Law%'" 2>/dev/null || echo "0")

if [ "$ITEM_CHECK" -eq 0 ]; then
    echo "Library missing target items, loading references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded" || echo "Warning: injection had issues"
else
    echo "Target items appear to exist ($ITEM_CHECK found)"
fi

# RESET STATE: Clear any existing journal abbreviations for the target items
# This ensures the agent isn't starting with the work already done (or partially done)
python3 -c "
import sqlite3
import sys

db_path = '$JURISM_DB'
targets = [
    'The Path of the Law',
    'Constitutional Fact Review',
    'The Due Process Clause and the Substantive Law of Torts'
]

try:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # Get fieldID for 'journalAbbreviation'
    c.execute(\"SELECT fieldID FROM fields WHERE fieldName='journalAbbreviation'\")
    row = c.fetchone()
    if not row:
        # Fallback or standard ID if not found in fields table (Jurism schema varies)
        # Usually 12, but we'll try to rely on the setup being clean if this fails
        print('Warning: journalAbbreviation field not found in schema')
        sys.exit(0)
    
    abbr_field_id = row[0]
    print(f'journalAbbreviation field ID: {abbr_field_id}')

    for title in targets:
        # Find item ID
        c.execute('''
            SELECT itemID FROM itemData 
            JOIN itemDataValues USING(valueID) 
            JOIN fields USING(fieldID) 
            WHERE fieldName='title' AND value=?
        ''', (title,))
        item_rows = c.fetchall()
        
        for item_row in item_rows:
            iid = item_row[0]
            # Delete any existing data for journalAbbreviation field for this item
            c.execute('DELETE FROM itemData WHERE itemID=? AND fieldID=?', (iid, abbr_field_id))
            print(f'Cleared abbreviation for item {iid} ({title})')

    conn.commit()
    conn.close()
    print('Reset complete')
except Exception as e:
    print(f'Error resetting DB: {e}')
"

# Remove any lingering journal file
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Record start timestamp
date +%s > /tmp/task_start_timestamp

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

# Take screenshot to verify start state
DISPLAY=:1 import -window root /tmp/abbr_task_start.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/abbr_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="