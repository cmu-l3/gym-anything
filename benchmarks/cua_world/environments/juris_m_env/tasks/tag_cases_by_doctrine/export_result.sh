#!/bin/bash
echo "=== Exporting tag_cases_by_doctrine results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get DB path
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Database not found"
    echo '{"error": "Database not found"}' > /tmp/task_result.json
    exit 1
fi

# Define Python script to inspect DB and generate JSON report
# We use Python here because complex SQL + JSON formatting in bash is error-prone
cat > /tmp/inspect_tags.py << 'PYEOF'
import sqlite3
import json
import sys
import os

db_path = sys.argv[1]
task_start = int(sys.argv[2])

targets = [
    {"term": "Brown v. Board", "id": None, "tags": []},
    {"term": "Miranda v. Arizona", "id": None, "tags": []},
    {"term": "New York Times", "id": None, "tags": []},
    {"term": "Gideon v. Wainwright", "id": None, "tags": []},
    {"term": "Path of the Law", "id": None, "tags": []}
]

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # For each target, find the itemID and then its tags
    for target in targets:
        # Find itemID by title or caseName
        # fieldID 1 = title, 58 = caseName
        cursor.execute("""
            SELECT items.itemID 
            FROM items 
            JOIN itemData ON items.itemID = itemData.itemID 
            JOIN itemDataValues ON itemData.valueID = itemDataValues.valueID 
            WHERE items.itemTypeID NOT IN (1, 3, 31) 
            AND itemData.fieldID IN (1, 58) 
            AND LOWER(itemDataValues.value) LIKE LOWER(?)
            LIMIT 1
        """, (f"%{target['term']}%",))
        
        row = cursor.fetchone()
        if row:
            target['id'] = row[0]
            
            # Get tags for this item
            cursor.execute("""
                SELECT tags.name 
                FROM itemTags 
                JOIN tags ON itemTags.tagID = tags.tagID 
                WHERE itemTags.itemID = ?
            """, (target['id'],))
            
            tags = [r[0] for r in cursor.fetchall()]
            target['tags'] = tags

    # Get total tag count change
    cursor.execute("SELECT COUNT(*) FROM itemTags")
    total_tags = cursor.fetchone()[0]

    result = {
        "targets": targets,
        "total_tags": total_tags,
        "task_start": task_start,
        "db_path": db_path
    }
    
    print(json.dumps(result, indent=2))
    conn.close()

except Exception as e:
    print(json.dumps({"error": str(e)}))

PYEOF

# Run inspection
python3 /tmp/inspect_tags.py "$JURISM_DB" "$TASK_START" > /tmp/tags_inspection.json

# Check if Jurism is running
APP_RUNNING=$(pgrep -f "jurism" > /dev/null && echo "true" || echo "false")

# Combine into final result
jq -n \
    --slurpfile data /tmp/tags_inspection.json \
    --arg start "$TASK_START" \
    --arg end "$TASK_END" \
    --arg running "$APP_RUNNING" \
    '{
        inspection: $data[0],
        meta: {
            task_start: $start,
            task_end: $end,
            app_running: $running,
            screenshot_path: "/tmp/task_final.png"
        }
    }' > /tmp/task_result.json

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="