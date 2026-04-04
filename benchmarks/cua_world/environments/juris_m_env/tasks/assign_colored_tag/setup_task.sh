#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up assign_colored_tag task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Find Jurism DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# 3. Stop Jurism to safely modify DB
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# 4. Inject Reference Data (if not already sufficient)
# We check count of non-system items
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 8 ]; then
    echo "Injecting legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB"
else
    echo "Library has sufficient items ($ITEM_COUNT)."
fi

# 5. Clean State: Remove any existing 'Landmark Decision' tags or colors
# This ensures the agent must create it from scratch.
echo "Cleaning up previous tag state..."
python3 -c "
import sqlite3
import sys

try:
    conn = sqlite3.connect('$JURISM_DB')
    cursor = conn.cursor()
    
    # Find tag ID for 'Landmark Decision'
    cursor.execute(\"SELECT tagID FROM tags WHERE name = 'Landmark Decision'\")
    rows = cursor.fetchall()
    tag_ids = [r[0] for r in rows]
    
    if tag_ids:
        print(f'Removing {len(tag_ids)} existing target tags...')
        for tid in tag_ids:
            # Remove item associations
            cursor.execute(\"DELETE FROM itemTags WHERE tagID = ?\", (tid,))
            # Remove from tags table
            cursor.execute(\"DELETE FROM tags WHERE tagID = ?\", (tid,))
            
    # Remove color settings for this tag from 'settings' and 'syncedSettings'
    # We delete generic tagColor settings to be safe, or specific ones if possible.
    # For simplicity, we'll try to remove settings containing the tag name.
    cursor.execute(\"DELETE FROM settings WHERE setting LIKE '%tagColor%' AND value LIKE '%Landmark Decision%'\")
    cursor.execute(\"DELETE FROM syncedSettings WHERE setting LIKE '%tagColor%' AND value LIKE '%Landmark Decision%'\")
    
    conn.commit()
    conn.close()
    print('Cleanup complete.')
except Exception as e:
    print(f'Error during cleanup: {e}')
"

# 6. Relaunch Jurism
echo "Relaunching Jurism..."
ensure_jurism_running

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="