#!/bin/bash
echo "=== Setting up restore_trashed_cases task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism for DB manipulation
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 1. Inject references to ensure targets exist
echo "Injecting legal references..."
python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null || echo "Injection warning"

# 2. Identify target Item IDs
# We look for the cases by name in itemData (fieldID 58 = caseName)
echo "Identifying target cases..."
cat > /tmp/find_ids.sql << EOF
SELECT items.itemID, value 
FROM items 
JOIN itemData ON items.itemID = itemData.itemID 
JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
WHERE fieldID = 58 
AND (
  value LIKE '%Brown%Board%Education%' OR 
  value LIKE '%Miranda%Arizona%' OR 
  value LIKE '%Gideon%Wainwright%'
)
AND items.itemTypeID NOT IN (1, 3, 31); -- Exclude attachments/notes
EOF

sqlite3 "$JURISM_DB" < /tmp/find_ids.sql > /tmp/target_items.txt

# Parse IDs into a JSON-like structure for the export script later
# Format: itemID|CaseName
ID_BROWN=$(grep "Brown" /tmp/target_items.txt | cut -d'|' -f1 | head -1)
ID_MIRANDA=$(grep "Miranda" /tmp/target_items.txt | cut -d'|' -f1 | head -1)
ID_GIDEON=$(grep "Gideon" /tmp/target_items.txt | cut -d'|' -f1 | head -1)

if [ -z "$ID_BROWN" ] || [ -z "$ID_MIRANDA" ] || [ -z "$ID_GIDEON" ]; then
    echo "ERROR: Failed to find all target cases in DB"
    cat /tmp/target_items.txt
    # Fallback: Try to run injection again if failed? 
    # For now, we rely on injection working.
fi

echo "Target IDs: Brown=$ID_BROWN, Miranda=$ID_MIRANDA, Gideon=$ID_GIDEON"

# Save IDs for export script
cat > /tmp/trashed_ids_info.txt << EOF
BROWN=$ID_BROWN
MIRANDA=$ID_MIRANDA
GIDEON=$ID_GIDEON
EOF

# 3. Move items to Trash (Insert into deletedItems table)
echo "Moving items to Trash..."
DATE_DELETED=$(date -u +"%Y-%m-%d %H:%M:%S")

sqlite3 "$JURISM_DB" << SQL
INSERT OR IGNORE INTO deletedItems (itemID, dateDeleted) VALUES ($ID_BROWN, '$DATE_DELETED');
INSERT OR IGNORE INTO deletedItems (itemID, dateDeleted) VALUES ($ID_MIRANDA, '$DATE_DELETED');
INSERT OR IGNORE INTO deletedItems (itemID, dateDeleted) VALUES ($ID_GIDEON, '$DATE_DELETED');
SQL

echo "Items moved to deletedItems table."

# Record initial count of active (non-trashed) items for data loss check
# In Zotero/Jurism, active items are those NOT in deletedItems
INITIAL_ACTIVE_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31) AND itemID NOT IN (SELECT itemID FROM deletedItems)" 2>/dev/null || echo "0")
echo "$INITIAL_ACTIVE_COUNT" > /tmp/initial_active_count
echo "Initial active items (excluding trash): $INITIAL_ACTIVE_COUNT"

# 4. Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for UI and handle alerts
wait_and_dismiss_jurism_alerts 45
ensure_jurism_running

# Take setup screenshot
take_screenshot /tmp/restore_task_start.png
echo "Setup screenshot saved"

echo "=== Task setup complete ==="