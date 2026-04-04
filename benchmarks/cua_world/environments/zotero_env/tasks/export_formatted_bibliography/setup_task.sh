#!/bin/bash
echo "=== Setting up export_formatted_bibliography task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists and clean previous output
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/thesis_chapter3_references.html
chown ga:ga /home/ga/Documents

# Zotero DB path
ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"

# Stop Zotero to modify DB safely
pkill -9 -f zotero 2>/dev/null || true
sleep 2

# Seed library with papers
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null

# Create specific collection and items via SQL
# We use a robust SQL approach to find item IDs by title and link them
sqlite3 "$ZOTERO_DB" <<'EOF'
-- Enable foreign keys
PRAGMA foreign_keys = ON;

-- Create the collection if it doesn't exist
INSERT INTO collections (collectionName, libraryID, parentCollectionID, key, version, synced)
SELECT 'Thesis Chapter 3', 1, NULL, 'THCH3KEY', 1, 0
WHERE NOT EXISTS (SELECT 1 FROM collections WHERE collectionName = 'Thesis Chapter 3');

-- Get the Collection ID
CREATE TEMP TABLE TargetColl AS SELECT collectionID FROM collections WHERE collectionName = 'Thesis Chapter 3';

-- Clear any existing items in this collection to ensure clean state
DELETE FROM collectionItems WHERE collectionID = (SELECT collectionID FROM TargetColl);

-- Insert items into collection based on titles
INSERT INTO collectionItems (collectionID, itemID, orderIndex)
SELECT 
    (SELECT collectionID FROM TargetColl),
    i.itemID,
    0
FROM items i
JOIN itemData d ON i.itemID = d.itemID
JOIN itemDataValues v ON d.valueID = v.valueID
WHERE d.fieldID = 1 -- Title field
AND (
    v.value LIKE '%Mathematical Theory of Communication%' OR
    v.value LIKE '%Computing Machinery and Intelligence%' OR
    v.value LIKE '%Attention Is All You Need%' OR
    v.value = 'Deep Learning' OR
    v.value LIKE '%Deep Residual Learning%'
);
EOF

echo "Collection 'Thesis Chapter 3' populated."

# Fix permissions
chown ga:ga "$ZOTERO_DB"

# Restart Zotero
echo "Starting Zotero..."
sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'

# Wait for Zotero window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Zotero window detected."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Wait a moment for UI to settle
sleep 5

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="