#!/bin/bash
echo "=== Exporting relate_cases Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_REL_COUNT=$(cat /tmp/initial_relation_count.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Get DB Path
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism DB not found"
    cat > /tmp/task_result.json << EOF
{
    "error": "Database not found",
    "passed": false,
    "timestamp": "$(date -Iseconds)"
}
EOF
    exit 1
fi

# Use Python to perform complex relation verification logic
# We need to map case names -> itemIDs -> itemKeys -> relations
python3 << PYSCRIPT
import sqlite3
import json
import os
import time

db_path = "$JURISM_DB"
task_start = $TASK_START
initial_count = int("$INITIAL_REL_COUNT")

result = {
    "task_start": task_start,
    "initial_relation_count": initial_count,
    "final_relation_count": 0,
    "relations_added": 0,
    "pairs": {},
    "error": None
}

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 1. Get current relation count
    cursor.execute("SELECT COUNT(*) FROM itemRelations")
    result["final_relation_count"] = cursor.fetchone()[0]
    result["relations_added"] = result["final_relation_count"] - initial_count

    # 2. Map required case names to (itemID, itemKey)
    # Note: 'value' is in itemDataValues, linked via itemData (fieldID=58 for caseName)
    # Using simple LIKE matching for robustness
    targets = {
        "brown": "Brown v. Board",
        "tinker": "Tinker v. Des Moines",
        "gideon": "Gideon v. Wainwright",
        "miranda": "Miranda v. Arizona",
        "nyt": "New York Times",
    }
    
    items = {}
    
    for key, search_term in targets.items():
        query = """
            SELECT i.itemID, i.key 
            FROM items i
            JOIN itemData id ON i.itemID = id.itemID
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            WHERE id.fieldID = 58 
            AND idv.value LIKE ? 
            LIMIT 1
        """
        cursor.execute(query, (f"%{search_term}%",))
        row = cursor.fetchone()
        if row:
            items[key] = {"id": row[0], "key": row[1]}
        else:
            items[key] = None

    # Helper to check relation
    def check_relation(item1, item2):
        if not item1 or not item2:
            return False
            
        # Zotero relations use itemKey in the object URI
        # e.g., "http://zotero.org/users/local/XXXX/items/KEY"
        
        # Check Forward: item1 -> item2
        q_fwd = "SELECT COUNT(*) FROM itemRelations WHERE itemID = ? AND object LIKE ?"
        cursor.execute(q_fwd, (item1['id'], f"%{item2['key']}"))
        fwd = cursor.fetchone()[0] > 0
        
        # Check Reverse: item2 -> item1
        q_rev = "SELECT COUNT(*) FROM itemRelations WHERE itemID = ? AND object LIKE ?"
        cursor.execute(q_rev, (item2['id'], f"%{item1['key']}"))
        rev = cursor.fetchone()[0] > 0
        
        return {"forward": fwd, "reverse": rev, "complete": fwd and rev}

    # 3. Check specific pairs
    pairs_to_check = [
        ("brown", "tinker"),
        ("gideon", "miranda"),
        ("nyt", "tinker")
    ]
    
    for k1, k2 in pairs_to_check:
        pair_name = f"{k1}_{k2}"
        if items[k1] and items[k2]:
            status = check_relation(items[k1], items[k2])
            result["pairs"][pair_name] = status
        else:
            result["pairs"][pair_name] = {"forward": False, "reverse": False, "complete": False, "missing_items": True}

    conn.close()

except Exception as e:
    result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)

PYSCRIPT

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="