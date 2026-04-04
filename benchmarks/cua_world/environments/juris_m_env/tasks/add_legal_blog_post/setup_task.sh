#!/bin/bash
echo "=== Setting up add_legal_blog_post task ==="
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

# 1. Inject background data if library is sparse (makes task realistic)
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Library is sparse, loading background legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null && echo "References loaded" || echo "Warning: injection had issues"
fi

# 2. CLEANUP: Ensure the target collection and item do not already exist
echo "Cleaning up any pre-existing task data..."
python3 -c "
import sqlite3
conn = sqlite3.connect('$JURISM_DB')
c = conn.cursor()

# Remove 'Web Research' collection
c.execute(\"SELECT collectionID FROM collections WHERE collectionName = 'Web Research'\")
rows = c.fetchall()
for row in rows:
    cid = row[0]
    c.execute(\"DELETE FROM collectionItems WHERE collectionID = ?\", (cid,))
    c.execute(\"DELETE FROM collections WHERE collectionID = ?\", (cid,))
    print(f\"Removed collection {cid}\")

# Remove specific blog post if it exists (check by title)
target_title = \"Court to decide whether 'testers' have standing to sue under ADA\"
c.execute(\"\"\"
    SELECT items.itemID FROM items 
    JOIN itemData ON items.itemID = itemData.itemID 
    JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
    WHERE itemDataValues.value LIKE ? 
\"\"\", (f'%{target_title}%',))
item_rows = c.fetchall()
for row in item_rows:
    iid = row[0]
    c.execute(\"DELETE FROM itemData WHERE itemID = ?\", (iid,))
    c.execute(\"DELETE FROM itemCreators WHERE itemID = ?\", (iid,))
    c.execute(\"DELETE FROM itemTags WHERE itemID = ?\", (iid,))
    c.execute(\"DELETE FROM items WHERE itemID = ?\", (iid,))
    print(f\"Removed item {iid}\")

conn.commit()
conn.close()
" 2>/dev/null || echo "Cleanup script failed or nothing to clean"

# Remove any lingering journal file
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# 3. Record start timestamp
date +%s > /tmp/task_start_timestamp

# 4. Relaunch Jurism
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
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="