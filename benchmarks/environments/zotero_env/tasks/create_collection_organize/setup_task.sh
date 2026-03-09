#!/bin/bash
echo "=== Setting up create_collection_organize task ==="

# Copy RIS file to Documents folder
mkdir -p /home/ga/Documents
cp /workspace/assets/sample_data/machine_learning_papers.ris /home/ga/Documents/
chown ga:ga /home/ga/Documents/machine_learning_papers.ris

# Record initial collection count and item count
ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"

if [ -f "$ZOTERO_DB" ]; then
    # Count collections
    INITIAL_COLL_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM collections" 2>/dev/null || echo "0")
    echo "$INITIAL_COLL_COUNT" > /tmp/initial_collection_count
    echo "Initial collection count: $INITIAL_COLL_COUNT"

    # Count items
    INITIAL_ITEM_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID != 14 AND itemTypeID != 1" 2>/dev/null || echo "0")
    echo "$INITIAL_ITEM_COUNT" > /tmp/initial_item_count
    echo "Initial item count: $INITIAL_ITEM_COUNT"
else
    echo "0" > /tmp/initial_collection_count
    echo "0" > /tmp/initial_item_count
    echo "Zotero database not found, starting from 0"
fi

# Ensure Zotero window is visible and maximized
sleep 2
echo "Verifying Zotero window state..."

# Check if window exists
if ! DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
    echo "⚠ WARNING: Zotero window not found in window list!"
    echo "Attempting to restart Zotero..."
    pkill -f zotero 2>/dev/null || true
    sleep 2
    sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero_restart.log 2>&1 &'
    sleep 10
fi

# Maximize and activate
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || echo "⚠ Maximize failed"
sleep 1
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || echo "⚠ Activate failed"
sleep 1

# Take screenshot to verify state
DISPLAY=:1 import -window root /tmp/task_start_verification.png 2>/dev/null

# Verify window is now visible
if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
    echo "✓ Zotero window verified"
else
    echo "✗ CRITICAL: Zotero window still not visible!"
fi

sleep 1
echo "=== Task setup complete ==="
