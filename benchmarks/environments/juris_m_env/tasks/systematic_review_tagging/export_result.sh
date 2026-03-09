#!/bin/bash
echo "=== Exporting systematic_review_tagging Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/systematic_review_end.png
echo "Screenshot saved to /tmp/systematic_review_end.png"

# Kill Jurism so SQLite is not locked during export
pkill -f "/opt/jurism/jurism" 2>/dev/null || true
sleep 3
echo "Jurism stopped for database export"

# Run Python to query DB and produce result JSON
python3 << 'PYEOF'
import sqlite3
import json
import os
import sys
from datetime import datetime

JURISM_DB = ""
for db_candidate in ["/home/ga/Jurism/jurism.sqlite", "/home/ga/Jurism/zotero.sqlite"]:
    if os.path.exists(db_candidate):
        JURISM_DB = db_candidate
        break

if not JURISM_DB:
    result = {"error": "Jurism database not found", "passed": False}
    with open("/tmp/systematic_review_tagging_result.json", "w") as f:
        json.dump(result, f, indent=2)
    print("ERROR: Cannot find Jurism database", file=sys.stderr)
    sys.exit(1)

conn = sqlite3.connect(JURISM_DB)
c = conn.cursor()

# ---- Find collections ----
c.execute("SELECT collectionID, collectionName FROM collections WHERE libraryID=1")
all_collections = c.fetchall()

included_id = None
excluded_id = None
included_collection_exists = False
excluded_collection_exists = False

for coll_id, coll_name in all_collections:
    name_lower = coll_name.lower()
    if "included" in name_lower and ("stud" in name_lower or "case" in name_lower or "review" in name_lower or name_lower == "included studies"):
        included_collection_exists = True
        included_id = coll_id
    elif "excluded" in name_lower and ("stud" in name_lower or "case" in name_lower or "review" in name_lower or name_lower == "excluded studies"):
        excluded_collection_exists = True
        excluded_id = coll_id

# Fallback: broader name match
if not included_collection_exists:
    for coll_id, coll_name in all_collections:
        if "included" in coll_name.lower():
            included_collection_exists = True
            included_id = coll_id
            break

if not excluded_collection_exists:
    for coll_id, coll_name in all_collections:
        if "excluded" in coll_name.lower():
            excluded_collection_exists = True
            excluded_id = coll_id
            break

# ---- Helper: get case names in a collection ----
def get_cases_in_collection(conn, collection_id):
    if collection_id is None:
        return []
    c = conn.cursor()
    c.execute(
        """
        SELECT idv.value
        FROM collectionItems ci
        JOIN items i ON ci.itemID = i.itemID
        JOIN itemData id ON i.itemID = id.itemID AND id.fieldID = 58
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        WHERE ci.collectionID = ?
        """,
        (collection_id,)
    )
    return [row[0] for row in c.fetchall()]

included_items = get_cases_in_collection(conn, included_id)
excluded_items = get_cases_in_collection(conn, excluded_id)

# ---- Get all item tags ----
c.execute(
    """
    SELECT
        COALESCE(
            (SELECT idv4.value FROM itemData id4
             JOIN itemDataValues idv4 ON id4.valueID = idv4.valueID
             WHERE id4.itemID = i.itemID AND id4.fieldID = 58),
            ''
        ) AS caseName,
        t.name AS tagName
    FROM items i
    JOIN itemTags it ON i.itemID = it.itemID
    JOIN tags t ON it.tagID = t.tagID
    WHERE i.libraryID = 1 AND i.itemTypeID NOT IN (1, 3, 31)
    """
)
all_item_tags = {}
for row in c.fetchall():
    case_name, tag_name = row
    if case_name:
        if case_name not in all_item_tags:
            all_item_tags[case_name] = []
        if tag_name not in all_item_tags[case_name]:
            all_item_tags[case_name].append(tag_name)

# Also include items with no tags (ensure all items appear in the dict)
c.execute(
    """
    SELECT COALESCE(
        (SELECT idv5.value FROM itemData id5
         JOIN itemDataValues idv5 ON id5.valueID = idv5.valueID
         WHERE id5.itemID = i.itemID AND id5.fieldID = 58),
        ''
    ) AS caseName
    FROM items i
    WHERE i.libraryID = 1 AND i.itemTypeID NOT IN (1, 3, 31)
    """
)
for row in c.fetchall():
    case_name = row[0]
    if case_name and case_name not in all_item_tags:
        all_item_tags[case_name] = []

# ---- Get notes attached to items in included collection ----
notes_on_included = []
if included_id is not None:
    c.execute(
        """
        SELECT
            COALESCE(
                (SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID
                 WHERE id.itemID=n.parentItemID AND id.fieldID=58),
                ''
            ) AS caseName,
            LENGTH(n.note) AS note_length
        FROM itemNotes n
        WHERE n.parentItemID IS NOT NULL AND n.parentItemID IN (
            SELECT ci.itemID FROM collectionItems ci WHERE ci.collectionID=?
        )
        """,
        (included_id,)
    )
    for row in c.fetchall():
        case_name, note_length = row
        notes_on_included.append({
            "caseName": case_name,
            "note_length": note_length,
        })

# ---- Total item count ----
c.execute("SELECT COUNT(*) FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)")
total_items = c.fetchone()[0]

conn.close()

result = {
    "included_collection_exists": included_collection_exists,
    "excluded_collection_exists": excluded_collection_exists,
    "included_items": included_items,
    "excluded_items": excluded_items,
    "all_item_tags": all_item_tags,
    "notes_on_included": notes_on_included,
    "total_items": total_items,
    "export_timestamp": datetime.now().isoformat(),
}

output_path = "/tmp/systematic_review_tagging_result.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {output_path}")
print(f"  included_collection_exists: {included_collection_exists}")
print(f"  excluded_collection_exists: {excluded_collection_exists}")
print(f"  included_items ({len(included_items)}): {included_items}")
print(f"  excluded_items ({len(excluded_items)}): {excluded_items}")
print(f"  notes_on_included ({len(notes_on_included)}): {notes_on_included}")
print(f"  total_items: {total_items}")
PYEOF

chmod 666 /tmp/systematic_review_tagging_result.json 2>/dev/null || true
echo "Result file permissions set."
echo "=== Export Complete ==="
