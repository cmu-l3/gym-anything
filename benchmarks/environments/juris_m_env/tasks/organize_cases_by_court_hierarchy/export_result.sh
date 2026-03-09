#!/bin/bash
echo "=== Exporting organize_cases_by_court_hierarchy Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Identifiers
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DB_PATH=$(get_jurism_db)

if [ -z "$DB_PATH" ]; then
    echo "ERROR: Jurism DB not found"
    # Create empty result
    echo '{"error": "DB not found"}' > /tmp/task_result.json
    exit 1
fi

# We need to export two main things:
# 1. The collection hierarchy (collections table)
# 2. The items within those collections (collectionItems table + item names)

# Create a temporary Python script to dump this data cleanly to JSON
# Using Python ensures we handle the relational logic and JSON formatting reliably
cat > /tmp/dump_structure.py << 'EOF'
import sqlite3
import json
import sys
import os

db_path = sys.argv[1]
output_path = sys.argv[2]

if not os.path.exists(db_path):
    print(f"Error: DB not found at {db_path}")
    sys.exit(1)

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
cursor = conn.cursor()

# 1. Get Collections
cursor.execute("SELECT collectionID, collectionName, parentCollectionID FROM collections")
collections = []
for row in cursor.fetchall():
    collections.append({
        "id": row['collectionID'],
        "name": row['collectionName'],
        "parent_id": row['parentCollectionID']
    })

# 2. Get Items in Collections
# We specifically want items that are Cases, so we join on itemData for Case Name (field 58)
# We only care about items that are actually in a collection
cursor.execute("""
    SELECT 
        ci.collectionID, 
        i.itemID, 
        idv.value as caseName 
    FROM collectionItems ci
    JOIN items i ON ci.itemID = i.itemID
    JOIN itemData id ON i.itemID = id.itemID
    JOIN itemDataValues idv ON id.valueID = idv.valueID
    WHERE id.fieldID = 58  -- Case Name field
""")

items_in_collections = []
for row in cursor.fetchall():
    items_in_collections.append({
        "collection_id": row['collectionID'],
        "item_id": row['itemID'],
        "case_name": row['caseName']
    })

result = {
    "collections": collections,
    "items": items_in_collections,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": os.popen("date -Iseconds").read().strip()
}

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

conn.close()
EOF

# Run the python dumper
python3 /tmp/dump_structure.py "$DB_PATH" /tmp/task_result.json

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json