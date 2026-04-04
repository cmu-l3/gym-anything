#!/bin/bash
echo "=== Exporting comparative_law_organization Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/comparative_law_end.png
echo "Screenshot saved to /tmp/comparative_law_end.png"

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
    with open("/tmp/comparative_law_organization_result.json", "w") as f:
        json.dump(result, f, indent=2)
    print("ERROR: Cannot find Jurism database", file=sys.stderr)
    sys.exit(1)

conn = sqlite3.connect(JURISM_DB)
c = conn.cursor()

# ---- Find parent collection ----
c.execute(
    "SELECT collectionID, collectionName FROM collections WHERE libraryID=1 AND LOWER(collectionName) LIKE LOWER('%comparative constitutional law%')"
)
parent_row = c.fetchone()
parent_collection_exists = parent_row is not None
parent_id = parent_row[0] if parent_row else None

# ---- Find subcollections ----
us_id = None
uk_id = None
canada_id = None
us_subcollection_exists = False
uk_subcollection_exists = False
canada_subcollection_exists = False

c.execute("SELECT collectionID, collectionName, parentCollectionID FROM collections WHERE libraryID=1")
all_collections = c.fetchall()

for coll_id, coll_name, parent_coll_id in all_collections:
    name_lower = coll_name.lower()
    if "us cases" in name_lower or "u.s. cases" in name_lower or name_lower == "us":
        us_subcollection_exists = True
        us_id = coll_id
    elif "uk cases" in name_lower or "u.k. cases" in name_lower or name_lower == "uk":
        uk_subcollection_exists = True
        uk_id = coll_id
    elif "canada cases" in name_lower or "canadian cases" in name_lower:
        canada_subcollection_exists = True
        canada_id = coll_id

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

us_items = get_cases_in_collection(conn, us_id)
uk_items = get_cases_in_collection(conn, uk_id)
canada_items = get_cases_in_collection(conn, canada_id)

# ---- Get court field for all items ----
c.execute(
    """
    SELECT
        COALESCE(
            (SELECT idv2.value FROM itemData id2
             JOIN itemDataValues idv2 ON id2.valueID = idv2.valueID
             WHERE id2.itemID = i.itemID AND id2.fieldID = 58),
            ''
        ) AS caseName,
        COALESCE(
            (SELECT idv3.value FROM itemData id3
             JOIN itemDataValues idv3 ON id3.valueID = idv3.valueID
             WHERE id3.itemID = i.itemID AND id3.fieldID = 60),
            ''
        ) AS court
    FROM items i
    WHERE i.libraryID = 1 AND i.itemTypeID NOT IN (1, 3, 31)
    """
)
all_items_court = {}
for row in c.fetchall():
    case_name, court = row
    if case_name:
        all_items_court[case_name] = court

# ---- Get tags for all items ----
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
item_tags = {}
for row in c.fetchall():
    case_name, tag_name = row
    if case_name:
        if case_name not in item_tags:
            item_tags[case_name] = []
        if tag_name not in item_tags[case_name]:
            item_tags[case_name].append(tag_name)

# Fill in empty tag lists for items with no tags
for case_name in all_items_court:
    if case_name not in item_tags:
        item_tags[case_name] = []

# ---- Total item count ----
c.execute("SELECT COUNT(*) FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)")
total_items = c.fetchone()[0]

conn.close()

result = {
    "parent_collection_exists": parent_collection_exists,
    "us_subcollection_exists": us_subcollection_exists,
    "uk_subcollection_exists": uk_subcollection_exists,
    "canada_subcollection_exists": canada_subcollection_exists,
    "us_items": us_items,
    "uk_items": uk_items,
    "canada_items": canada_items,
    "all_items_court": all_items_court,
    "item_tags": item_tags,
    "total_items": total_items,
    "export_timestamp": datetime.now().isoformat(),
}

output_path = "/tmp/comparative_law_organization_result.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {output_path}")
print(f"  parent_collection_exists: {parent_collection_exists}")
print(f"  us_subcollection_exists: {us_subcollection_exists}")
print(f"  uk_subcollection_exists: {uk_subcollection_exists}")
print(f"  canada_subcollection_exists: {canada_subcollection_exists}")
print(f"  us_items ({len(us_items)}): {us_items}")
print(f"  uk_items ({len(uk_items)}): {uk_items}")
print(f"  canada_items ({len(canada_items)}): {canada_items}")
print(f"  total_items: {total_items}")
PYEOF

chmod 666 /tmp/comparative_law_organization_result.json 2>/dev/null || true
echo "Result file permissions set."
echo "=== Export Complete ==="
