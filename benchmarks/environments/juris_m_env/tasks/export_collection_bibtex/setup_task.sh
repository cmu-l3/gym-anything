#!/bin/bash
set -e
echo "=== Setting up export_collection_bibtex task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Jurism is running to handle any first-run logic, then kill it for DB setup
ensure_jurism_running
echo "Stopping Jurism for database setup..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 5

# Get database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Could not find Jurism database"
    exit 1
fi
echo "Using database: $DB_PATH"

# Inject all 10 legal references (real data)
echo "Injecting legal references..."
python3 /workspace/utils/inject_references.py "$DB_PATH" 2>/dev/null || true

# Verify items loaded
INITIAL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
echo "Initial item count: $INITIAL_COUNT"

# Create the "First Amendment Jurisprudence" collection
echo "Creating collection..."
# Clean up if it exists from a previous run
COLL_ID=$(sqlite3 "$DB_PATH" "SELECT collectionID FROM collections WHERE collectionName = 'First Amendment Jurisprudence' LIMIT 1")
if [ -n "$COLL_ID" ]; then
    sqlite3 "$DB_PATH" "DELETE FROM collectionItems WHERE collectionID = $COLL_ID"
    sqlite3 "$DB_PATH" "DELETE FROM collections WHERE collectionID = $COLL_ID"
fi

# Insert collection
sqlite3 "$DB_PATH" <<'SQL'
INSERT INTO collections (collectionName, clientDateModified, libraryID, key, version, synced)
VALUES ('First Amendment Jurisprudence', datetime('now'), 1, 'FA1STCOL', 0, 0);
SQL

# Get the new collection ID
COLL_ID=$(sqlite3 "$DB_PATH" "SELECT collectionID FROM collections WHERE collectionName = 'First Amendment Jurisprudence' LIMIT 1")
echo "Created Collection ID: $COLL_ID"

if [ -z "$COLL_ID" ]; then
    echo "ERROR: Failed to create collection"
    exit 1
fi

# Find itemIDs for the specific cases (Sullivan and Tinker)
# fieldID 58 is caseName in Jurism
SULLIVAN_ID=$(sqlite3 "$DB_PATH" "SELECT items.itemID FROM items JOIN itemData ON items.itemID = itemData.itemID JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID WHERE fieldID = 58 AND value LIKE '%Sullivan%' LIMIT 1")
TINKER_ID=$(sqlite3 "$DB_PATH" "SELECT items.itemID FROM items JOIN itemData ON items.itemID = itemData.itemID JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID WHERE fieldID = 58 AND value LIKE '%Tinker%' LIMIT 1")

echo "Sullivan itemID: $SULLIVAN_ID"
echo "Tinker itemID: $TINKER_ID"

if [ -z "$SULLIVAN_ID" ] || [ -z "$TINKER_ID" ]; then
    echo "ERROR: Could not find required case items in database"
    exit 1
fi

# Add cases to the collection
sqlite3 "$DB_PATH" <<SQL
INSERT OR IGNORE INTO collectionItems (collectionID, itemID, orderIndex) VALUES ($COLL_ID, $SULLIVAN_ID, 0);
INSERT OR IGNORE INTO collectionItems (collectionID, itemID, orderIndex) VALUES ($COLL_ID, $TINKER_ID, 1);
SQL

# Clean up any previous export files to prevent false positives
rm -f /home/ga/Documents/first_amendment_refs.bib
rm -f /home/ga/Documents/first_amendment_refs*.bib

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents
chown ga:ga "$DB_PATH"

# Restart Jurism to pick up DB changes
echo "Restarting Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote > /home/ga/jurism_task.log 2>&1 &'
sleep 8

# Dismiss alerts and maximize
wait_and_dismiss_jurism_alerts 45
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true
sleep 2

# Take initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="