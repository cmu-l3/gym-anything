#!/bin/bash
echo "=== Exporting catalog_and_link_dataset result ==="

# 1. Capture final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get environment info
DB="/home/ga/Zotero/zotero.sqlite"
TARGET_ID=$(cat /tmp/target_paper_id 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Use Python to inspect the database thoroughly
# We use Python here because complex joins and field lookups are messy in bash/sqlite3 CLI
# and we need to handle field IDs dynamically if possible, or robustly.

python3 << PYEOF
import sqlite3
import json
import os
import sys

db_path = "$DB"
target_id = int("$TARGET_ID")
task_start = int("$TASK_START")

result = {
    "dataset_found": False,
    "dataset_item_id": None,
    "title_correct": False,
    "author_found": False,
    "date_correct": False,
    "url_correct": False,
    "repository_correct": False,
    "relation_found": False,
    "created_after_start": False,
    "metadata_captured": {}
}

try:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # 1. Find the Dataset item
    # Look for items of type 'dataset' (itemTypeID needs lookup or hardcode)
    # Zotero 7 itemTypes: usually 'dataset' is distinct. Let's find its ID.
    cur.execute("SELECT itemTypeID FROM itemTypes WHERE typeName = 'dataset'")
    row = cur.fetchone()
    if not row:
        # Fallback if 'dataset' type name differs (unlikely in standard Zotero)
        dataset_type_id = -1
    else:
        dataset_type_id = row['itemTypeID']

    # Find items of this type added recently or matching title
    # We look for ANY dataset item first, then check metadata
    cur.execute("""
        SELECT i.itemID, i.dateAdded
        FROM items i
        WHERE i.itemTypeID = ? AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    """, (dataset_type_id,))
    
    candidates = cur.fetchall()
    
    # Filter for the one that looks like ImageNet
    best_candidate = None
    
    for cand in candidates:
        item_id = cand['itemID']
        
        # Get all fields for this item
        cur.execute("""
            SELECT f.fieldName, v.value
            FROM itemData d
            JOIN fields f ON d.fieldID = f.fieldID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE d.itemID = ?
        """, (item_id,))
        fields = {r['fieldName']: r['value'] for r in cur.fetchall()}
        
        # Check title loosely to identify candidacy
        title = fields.get('title', '')
        if 'ImageNet' in title:
            best_candidate = {'id': item_id, 'fields': fields, 'dateAdded': cand['dateAdded']}
            break

    if best_candidate:
        result["dataset_found"] = True
        result["dataset_item_id"] = best_candidate['id']
        fields = best_candidate['fields']
        result["metadata_captured"] = fields

        # Check Fields
        if "ImageNet: A Large-Scale Hierarchical Image Database" in fields.get('title', ''):
            result["title_correct"] = True
        
        if "2009" in fields.get('date', ''):
            result["date_correct"] = True
            
        if "image-net.org" in fields.get('url', ''):
            result["url_correct"] = True
            
        if "Princeton Vision Lab" in fields.get('repository', ''):
            result["repository_correct"] = True

        # Check Creator (Author)
        cur.execute("""
            SELECT c.lastName, c.firstName
            FROM itemCreators ic
            JOIN creators c ON ic.creatorID = c.creatorID
            WHERE ic.itemID = ?
        """, (best_candidate['id'],))
        creators = cur.fetchall()
        for c in creators:
            if "Deng" in c['lastName']:
                result["author_found"] = True
                break

        # Check Relation to Krizhevsky paper
        # Relations can be in itemRelations table
        # bidirectional check: itemID -> relatedItemID OR relatedItemID -> itemID
        cur.execute("""
            SELECT count(*) as cnt 
            FROM itemRelations 
            WHERE (itemID = ? AND relatedItemID = ?) 
               OR (itemID = ? AND relatedItemID = ?)
        """, (best_candidate['id'], target_id, target_id, best_candidate['id']))
        if cur.fetchone()['cnt'] > 0:
            result["relation_found"] = True

    conn.close()

except Exception as e:
    result["error"] = str(e)

# Write result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="