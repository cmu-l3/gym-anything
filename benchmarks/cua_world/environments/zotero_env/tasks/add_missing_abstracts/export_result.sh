#!/bin/bash
echo "=== Exporting add_missing_abstracts result ==="

ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Function to get abstract for a specific title
# fieldID 1 = title, fieldID 2 = abstractNote
get_abstract_info() {
    local search_title="$1"
    
    # We use python to handle potential special characters/newlines in SQL output better than pure bash
    python3 << ENDPY
import sqlite3
import json
import sys

db_path = "$ZOTERO_DB"
search_title = "$search_title"
task_start = int($TASK_START)

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Find itemID for title
    query = """
        SELECT i.itemID, i.dateModified 
        FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE d.fieldID = 1 AND v.value LIKE ?
        LIMIT 1
    """
    cursor.execute(query, ('%' + search_title + '%',))
    row = cursor.fetchone()
    
    result = {
        "found": False,
        "abstract": "",
        "modified_recently": False,
        "item_id": None
    }
    
    if row:
        item_id = row[0]
        # Check modification time (Zotero stores as string 'YYYY-MM-DD HH:MM:SS')
        # We'll just pass the raw date string back for python verifier to parse if needed, 
        # or do a rough check here. simpler to check if abstract exists.
        
        result["found"] = True
        result["item_id"] = item_id
        
        # Get Abstract
        abs_query = """
            SELECT v.value 
            FROM itemData d
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.itemID = ? AND d.fieldID = 2
        """
        cursor.execute(abs_query, (item_id,))
        abs_row = cursor.fetchone()
        if abs_row:
            result["abstract"] = abs_row[0]

    print(json.dumps(result))
    conn.close()
except Exception as e:
    print(json.dumps({"error": str(e)}))
ENDPY
}

# Extract data for the 3 target papers
echo "Extracting data for Paper 1..."
PAPER1_JSON=$(get_abstract_info "Attention Is All You Need")
echo "Extracting data for Paper 2..."
PAPER2_JSON=$(get_abstract_info "Generative Adversarial Nets")
echo "Extracting data for Paper 3..."
PAPER3_JSON=$(get_abstract_info "Deep Learning")

# Get global counts
INITIAL_COUNT=$(cat /tmp/initial_abstract_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM itemData WHERE fieldID = 2" 2>/dev/null || echo "0")

# Compile into final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_abstract_count": $INITIAL_COUNT,
    "final_abstract_count": $FINAL_COUNT,
    "paper1": $PAPER1_JSON,
    "paper2": $PAPER2_JSON,
    "paper3": $PAPER3_JSON
}
EOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="