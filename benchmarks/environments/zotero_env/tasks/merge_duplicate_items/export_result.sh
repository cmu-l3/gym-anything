#!/bin/bash
echo "=== Exporting merge_duplicate_items result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

DB_PATH="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create Python script to analyze DB state
cat > /tmp/analyze_result.py << 'PYEOF'
import sqlite3
import json
import os

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
TASK_START = int(os.environ.get("TASK_START", 0))

def get_field_value(conn, item_id, field_id):
    cur = conn.cursor()
    cur.execute("""
        SELECT v.value 
        FROM itemData d 
        JOIN itemDataValues v ON d.valueID = v.valueID 
        WHERE d.itemID = ? AND d.fieldID = ?
    """, (item_id, field_id))
    row = cur.fetchone()
    return row[0] if row else None

try:
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    
    # 1. Count active bibliographic items (exclude notes(1), attachments(14), annotations(28))
    # And exclude deleted items
    cur.execute("""
        SELECT COUNT(*) FROM items 
        WHERE itemTypeID NOT IN (1, 14, 28) 
        AND itemID NOT IN (SELECT itemID FROM deletedItems)
    """)
    final_count = cur.fetchone()[0]
    
    # 2. Count trash items
    cur.execute("SELECT COUNT(*) FROM deletedItems")
    trash_count = cur.fetchone()[0]
    
    # 3. Check specific items metadata
    checks = [
        {"name": "Attention", "title": "Attention Is All You Need", "field": 19, "expected": "30"},
        {"name": "Deep Learning", "title": "Deep Learning", "field": 59, "expected": "10.1038/nature14539"},
        {"name": "Shannon", "title": "Mathematical Theory of Communication", "field": 32, "expected": "379-423"},
        {"name": "Turing", "title": "Computing Machinery and Intelligence", "field": 6, "expected": "1950"}
    ]
    
    metadata_results = {}
    
    for check in checks:
        # Find the active item(s) matching title
        cur.execute("""
            SELECT i.itemID 
            FROM items i
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.fieldID = 1 
            AND v.value LIKE ? 
            AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
        """, (f"%{check['title']}%",))
        
        items = cur.fetchall()
        
        if not items:
            metadata_results[check['name']] = {"status": "missing", "value": None}
            continue
            
        # Ideally should be only 1 item if merged
        item_id = items[0][0]
        actual_value = get_field_value(conn, item_id, check['field'])
        
        # Approximate matching for date (contains 1950) or exact for others
        passed = False
        if check['field'] == 6: # Date
            passed = (check['expected'] in str(actual_value))
        else:
            passed = (str(actual_value) == check['expected'])
            
        metadata_results[check['name']] = {
            "status": "correct" if passed else "incorrect",
            "value": actual_value,
            "count": len(items)
        }
        
    result = {
        "final_count": final_count,
        "trash_count": trash_count,
        "metadata_checks": metadata_results,
        "db_exists": True
    }
    
    print(json.dumps(result))
    conn.close()
    
except Exception as e:
    print(json.dumps({"error": str(e), "db_exists": False}))
PYEOF

# Run analysis
export TASK_START
ANALYSIS_JSON=$(python3 /tmp/analyze_result.py)

# Create final JSON
cat > /tmp/temp_result.json << EOF
{
    "task_start": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "analysis": $ANALYSIS_JSON
}
EOF

# Move to safe location
mv /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="