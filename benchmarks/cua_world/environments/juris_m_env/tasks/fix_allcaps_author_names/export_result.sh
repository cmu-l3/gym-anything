#!/bin/bash
echo "=== Exporting fix_allcaps_author_names result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get database path
DB_PATH=$(get_jurism_db)
if [ -z "$DB_PATH" ]; then
    echo "ERROR: Cannot find Jurism database"
    # Create empty result to avoid verifier crash, but indicate failure
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# Export data using a python script to query the SQLite DB cleanly
# We need to extract the current author names for the three target books
cat > /tmp/export_data.py << 'EOF'
import sys
import sqlite3
import json

db_path = sys.argv[1]
output_file = sys.argv[2]

TARGETS = {
    "The Common Law": "holmes",
    "Leviathan": "hobbes",
    "The Spirit of Laws": "montesquieu"
}

results = {
    "holmes": None,
    "hobbes": None,
    "montesquieu": None,
    "error": None
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    for title, key in TARGETS.items():
        # Find item by title
        # Note: fieldID 1 is Title in Jurism schema
        query = """
            SELECT c.firstName, c.lastName, c.fieldMode
            FROM items i
            JOIN itemData id ON i.itemID = id.itemID
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            JOIN itemCreators ic ON i.itemID = ic.itemID
            JOIN creators c ON ic.creatorID = c.creatorID
            WHERE id.fieldID = 1 AND idv.value = ?
            ORDER BY ic.orderIndex ASC
            LIMIT 1
        """
        cursor.execute(query, (title,))
        row = cursor.fetchone()
        
        if row:
            results[key] = {
                "firstName": row[0],
                "lastName": row[1],
                "fieldMode": row[2]
            }
        else:
            # Item not found or no creator attached
            results[key] = "not_found"

    conn.close()

except Exception as e:
    results["error"] = str(e)

with open(output_file, 'w') as f:
    json.dump(results, f, indent=2)
EOF

# Run export script
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 /tmp/export_data.py "$DB_PATH" "$TEMP_JSON"

# Move to final location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="