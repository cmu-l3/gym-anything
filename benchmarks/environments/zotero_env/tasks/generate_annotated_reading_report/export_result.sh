#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
DB="/home/ga/Zotero/zotero.sqlite"
OUTPUT_PATH="/home/ga/Documents/ai_seminar_report.html"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE=0
REPORT_CONTENT_VALID="false"

if [ -f "$OUTPUT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Check content for key strings (grep returns 0 if found)
    if grep -q "Essential reading" "$OUTPUT_PATH" && \
       grep -q "Computing Machinery" "$OUTPUT_PATH" && \
       grep -q "Shannon" "$OUTPUT_PATH"; then
        REPORT_CONTENT_VALID="true"
    fi
fi

# 2. Check Database State
# Python script to query DB reliably
python3 << PYEOF
import sqlite3
import json

db_path = "$DB"
result = {
    "collection_exists": False,
    "collection_item_count": 0,
    "correct_items_present": False,
    "note_exists": False,
    "note_attached_correctly": False
}

target_papers = [
    "Computing Machinery and Intelligence",
    "On Computable Numbers",
    "A Mathematical Theory of Communication",
    "Recursive Functions of Symbolic Expressions"
]
target_note = "Essential reading: Discusses the Imitation Game"

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    
    # Check collection
    cur.execute("SELECT collectionID FROM collections WHERE collectionName='AI History Seminar'")
    row = cur.fetchone()
    if row:
        result["collection_exists"] = True
        coll_id = row[0]
        
        # Check items in collection
        cur.execute("SELECT count(*) FROM collectionItems WHERE collectionID=?", (coll_id,))
        result["collection_item_count"] = cur.fetchone()[0]
        
        # Check if specific papers are in collection
        # (Simplified check: count how many target titles are linked to this collection)
        placeholders = ','.join(['?'] * len(target_papers))
        # Need to join items -> itemData -> itemDataValues
        query = f"""
            SELECT count(DISTINCT i.itemID)
            FROM collectionItems ci
            JOIN items i ON ci.itemID = i.itemID
            JOIN itemData id ON i.itemID = id.itemID
            JOIN itemDataValues idv ON id.valueID = idv.valueID
            WHERE ci.collectionID = ?
            AND id.fieldID = 1 -- Title
            AND idv.value IN ({placeholders})
        """
        params = [coll_id] + target_papers
        cur.execute(query, params)
        count = cur.fetchone()[0]
        # We expect 4 unique matches (titles are unique enough in this small set)
        if count >= 3: # Allow slight leniency if title matching is fuzzy
            result["correct_items_present"] = True
            
    # Check note
    # Note content is HTML encoded in DB usually, looking for substring
    cur.execute("SELECT parentItemID FROM itemNotes WHERE note LIKE ?", (f'%{target_note}%',))
    note_rows = cur.fetchall()
    if note_rows:
        result["note_exists"] = True
        # Check if parent is Turing 1950
        for parent_id in [r[0] for r in note_rows]:
            # Get title of parent
            cur.execute("""
                SELECT idv.value 
                FROM itemData id 
                JOIN itemDataValues idv ON id.valueID = idv.valueID
                WHERE id.itemID = ? AND id.fieldID = 1
            """, (parent_id,))
            title_row = cur.fetchone()
            if title_row and "Computing Machinery" in title_row[0]:
                result["note_attached_correctly"] = True
                break

    conn.close()
except Exception as e:
    result["error"] = str(e)

with open("/tmp/db_check.json", "w") as f:
    json.dump(result, f)
PYEOF

# Merge DB results
if [ -f "/tmp/db_check.json" ]; then
    DB_JSON=$(cat /tmp/db_check.json)
else
    DB_JSON="{}"
fi

# Create final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size": $REPORT_SIZE,
    "report_content_valid": $REPORT_CONTENT_VALID,
    "db_state": $DB_JSON
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="