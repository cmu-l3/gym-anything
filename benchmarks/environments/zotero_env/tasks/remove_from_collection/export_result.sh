#!/bin/bash
# Export result for remove_from_collection task

echo "=== Exporting remove_from_collection result ==="

DB="/home/ga/Zotero/zotero.sqlite"
ORIGINAL_COLL_ID=$(cat /tmp/original_collection_id.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Allow DB to flush
sleep 2

# Use Python for complex verification logic
python3 << PYEOF
import sqlite3
import json
import os

db_path = "$DB"
orig_coll_id = int("$ORIGINAL_COLL_ID")

result = {
    "collection_exists": False,
    "collection_id_match": False,
    "final_collection_count": 0,
    "removed_papers_status": {},
    "kept_papers_status": {},
    "timestamp": "$(date -Iseconds)"
}

titles_to_remove = [
    "On the Electrodynamics of Moving Bodies",
    "Molecular Structure of Nucleic Acids: A Structure for Deoxyribose Nucleic Acid",
    "Generative Adversarial Nets",
    "Mastering the Game of Go with Deep Neural Networks and Tree Search"
]

titles_to_keep = [
    "Attention Is All You Need",
    "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding",
    "Language Models are Few-Shot Learners",
    "Deep Learning",
    "Deep Residual Learning for Image Recognition",
    "On Computable Numbers, with an Application to the Entscheidungsproblem",
    "A Mathematical Theory of Communication",
    "Computing Machinery and Intelligence"
]

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 1. Verify Collection Existence and Identity
    cursor.execute("SELECT collectionID FROM collections WHERE collectionName = 'Thesis References'")
    row = cursor.fetchone()
    if row:
        current_id = row[0]
        result["collection_exists"] = True
        result["collection_id_match"] = (current_id == orig_coll_id)
        target_coll_id = current_id # Use current ID for checking items if it exists
    else:
        target_coll_id = orig_coll_id # Fallback to check if empty

    # 2. Check Collection Count
    if result["collection_exists"]:
        cursor.execute("SELECT COUNT(*) FROM collectionItems WHERE collectionID = ?", (target_coll_id,))
        result["final_collection_count"] = cursor.fetchone()[0]

    # Helper to check item status
    def check_paper(title):
        # Find item ID
        cursor.execute("""
            SELECT i.itemID FROM items i
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.fieldID = 1 AND v.value = ?
        """, (title,))
        row = cursor.fetchone()
        if not row:
            return {"found": False, "in_collection": False, "in_library": False, "trashed": False}
        
        item_id = row[0]
        
        # Check if in collection
        cursor.execute("SELECT 1 FROM collectionItems WHERE collectionID = ? AND itemID = ?", (target_coll_id, item_id))
        in_coll = (cursor.fetchone() is not None)
        
        # Check if trashed
        cursor.execute("SELECT 1 FROM deletedItems WHERE itemID = ?", (item_id,))
        trashed = (cursor.fetchone() is not None)
        
        # Check if in library (exists in items and not trashed)
        in_lib = (not trashed)
        
        return {
            "found": True, 
            "in_collection": in_coll, 
            "in_library": in_lib, 
            "trashed": trashed
        }

    # 3. Check Removed Papers
    for title in titles_to_remove:
        result["removed_papers_status"][title] = check_paper(title)

    # 4. Check Kept Papers
    for title in titles_to_keep:
        result["kept_papers_status"][title] = check_paper(title)

    conn.close()

except Exception as e:
    result["error"] = str(e)

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="