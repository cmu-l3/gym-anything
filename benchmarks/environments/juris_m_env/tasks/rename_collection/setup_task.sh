#!/bin/bash
set -e
echo "=== Setting up rename_collection task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source utilities
source /workspace/scripts/task_utils.sh

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    # Fallback search if utils fail
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
echo "Database path: $JURISM_DB"

# Kill Jurism temporarily to safely modify the database (DB is locked when app is running)
echo "Stopping Jurism for setup..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject legal references into the database (ensures we have items to put in the collection)
python3 /workspace/utils/inject_references.py "$JURISM_DB"
echo "Legal references injected"

# Create the "Research" collection via SQLite
# We check if it exists first to avoid duplicates or errors
EXISTING_ID=$(sqlite3 "$JURISM_DB" "SELECT collectionID FROM collections WHERE collectionName='Research' LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$EXISTING_ID" ]; then
    # Generate a random key (Jurism uses 8-char alphanumeric keys)
    COLL_KEY=$(cat /dev/urandom | tr -dc 'A-Z0-9' | fold -w 8 | head -n 1)
    
    # Insert collection
    sqlite3 "$JURISM_DB" <<SQL
INSERT INTO collections (collectionName, libraryID, key, dateAdded, dateModified, clientDateModified)
VALUES ('Research', 1, '$COLL_KEY', datetime('now'), datetime('now'), datetime('now'));
SQL
    EXISTING_ID=$(sqlite3 "$JURISM_DB" "SELECT last_insert_rowid();")
    echo "Created 'Research' collection (ID=$EXISTING_ID)"
else
    echo "'Research' collection already exists (ID=$EXISTING_ID)"
fi

# Clear any existing items in this collection to ensure clean state
sqlite3 "$JURISM_DB" "DELETE FROM collectionItems WHERE collectionID=$EXISTING_ID;"

# Add 5 random case items to this collection
# itemTypeID != 1 (attachment), 3 (note), 14 (attachment link?), 31 (annotation)
sqlite3 "$JURISM_DB" <<SQL
INSERT OR IGNORE INTO collectionItems (collectionID, itemID, orderIndex)
SELECT $EXISTING_ID, itemID, ROW_NUMBER() OVER (ORDER BY random()) - 1
FROM items
WHERE itemTypeID NOT IN (1, 3, 14, 31)
LIMIT 5;
SQL

# Record initial state for verification
INITIAL_ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM collectionItems WHERE collectionID=$EXISTING_ID;" 2>/dev/null || echo "0")

echo "$EXISTING_ID" > /tmp/initial_collection_id.txt
echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count.txt

cat > /tmp/initial_state.json <<EOF
{
  "collection_id": $EXISTING_ID,
  "item_count": $INITIAL_ITEM_COUNT,
  "old_name": "Research"
}
EOF

echo "Initial state recorded: Collection ID=$EXISTING_ID, Items=$INITIAL_ITEM_COUNT"

# Ensure proper ownership of DB after root modification
chown ga:ga "$JURISM_DB"
# Remove journal file if it exists (cleanup from direct DB access)
rm -f "${JURISM_DB}-journal" 2>/dev/null || true

# Restart Jurism
echo "Restarting Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'
sleep 10

# Dismiss any alerts (e.g. jurisdiction updates)
wait_and_dismiss_jurism_alerts 30

# Maximize and focus
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Select the "Research" collection in the UI if possible?
# UI automation is tricky here without xdotool coordinates which vary.
# We assume the user can find "Research" in the list.

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== rename_collection task setup complete ==="