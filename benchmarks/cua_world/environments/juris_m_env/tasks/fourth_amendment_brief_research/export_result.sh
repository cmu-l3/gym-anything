#!/bin/bash

echo "=== Exporting fourth_amendment_brief_research results ==="

JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then JURISM_DB="$db_candidate"; break; fi
done

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism database not found"
    exit 1
fi

echo "Using database: $JURISM_DB"

# Kill Jurism so SQLite is not locked during export
pkill -f "/opt/jurism/jurism" 2>/dev/null || true
sleep 3
echo "Jurism stopped for database export"

python3 << 'PYEOF'
import sqlite3, json, os
from datetime import datetime

JURISM_DB = ""
for db_candidate in ["/home/ga/Jurism/jurism.sqlite", "/home/ga/Jurism/zotero.sqlite"]:
    if os.path.exists(db_candidate):
        JURISM_DB = db_candidate
        break

if not JURISM_DB:
    print("ERROR: Jurism database not found")
    import sys; sys.exit(1)

conn = sqlite3.connect(JURISM_DB)
conn.row_factory = sqlite3.Row
c = conn.cursor()

# Total items in user library
c.execute("SELECT COUNT(*) FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)")
total_items = c.fetchone()[0]

# All cases with key fields
c.execute("""
SELECT
  i.itemID,
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=58),'') as caseName,
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=60),'') as court,
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=49),'') as reporter,
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=66),'') as reporterVolume,
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=67),'') as firstPage,
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=69),'') as dateDecided
FROM items i
WHERE i.libraryID=1 AND i.itemTypeID NOT IN (1,3,31)
""")
rows = c.fetchall()
all_cases = []
item_id_to_name = {}
for row in rows:
    d = dict(row)
    item_id_to_name[d["itemID"]] = d["caseName"]
    all_cases.append({k: v for k, v in d.items() if k != "itemID"})

# All tags per case
c.execute("""
SELECT
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=it.itemID AND id.fieldID=58),'') as caseName,
  t.name as tagName
FROM itemTags it
JOIN tags t ON it.tagID=t.tagID
WHERE it.itemID IN (SELECT itemID FROM items WHERE libraryID=1)
""")
all_case_tags = {}
for row in c.fetchall():
    name = row["caseName"]
    tag = row["tagName"]
    if name not in all_case_tags:
        all_case_tags[name] = []
    all_case_tags[name].append(tag)

# Check for parent collection 'Fourth Amendment Research'
c.execute("""
SELECT collectionID FROM collections
WHERE collectionName='Fourth Amendment Research' AND libraryID=1 AND parentCollectionID IS NULL
""")
parent_row = c.fetchone()
parent_collection_exists = parent_row is not None
parent_col_id = parent_row["collectionID"] if parent_row else None

# Check for subcollections
favorable_collection_exists = False
adverse_collection_exists = False
favorable_col_id = None
adverse_col_id = None

if parent_col_id is not None:
    c.execute("""
    SELECT collectionID, collectionName FROM collections
    WHERE parentCollectionID=? AND libraryID=1
    """, (parent_col_id,))
    subcols = c.fetchall()
    for sc in subcols:
        if "favorable" in sc["collectionName"].lower():
            favorable_collection_exists = True
            favorable_col_id = sc["collectionID"]
        if "adverse" in sc["collectionName"].lower():
            adverse_collection_exists = True
            adverse_col_id = sc["collectionID"]

# Items in favorable subcollection
favorable_items = []
if favorable_col_id is not None:
    c.execute("""
    SELECT ci.itemID FROM collectionItems ci
    WHERE ci.collectionID=?
    """, (favorable_col_id,))
    for row in c.fetchall():
        iid = row["itemID"]
        name = item_id_to_name.get(iid, "")
        if name:
            favorable_items.append(name)

# Items in adverse subcollection
adverse_items = []
if adverse_col_id is not None:
    c.execute("""
    SELECT ci.itemID FROM collectionItems ci
    WHERE ci.collectionID=?
    """, (adverse_col_id,))
    for row in c.fetchall():
        iid = row["itemID"]
        name = item_id_to_name.get(iid, "")
        if name:
            adverse_items.append(name)

# Notes attached to items
c.execute("""
SELECT
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=n.parentItemID AND id.fieldID=58),'unknown') as caseName,
  LENGTH(n.note) as note_length
FROM itemNotes n
WHERE n.parentItemID IS NOT NULL
""")
notes = [dict(row) for row in c.fetchall()]

# Verify pre-existing items still present
PREEXISTING_NAMES = ["Marbury v. Madison", "Brown v. Board of Education"]
preexisting_cases = []
for row in rows:
    if row["caseName"] in PREEXISTING_NAMES:
        preexisting_cases.append(row["caseName"])

result = {
    "total_items": total_items,
    "all_cases": all_cases,
    "all_case_tags": all_case_tags,
    "parent_collection_exists": parent_collection_exists,
    "favorable_collection_exists": favorable_collection_exists,
    "adverse_collection_exists": adverse_collection_exists,
    "favorable_items": favorable_items,
    "adverse_items": adverse_items,
    "notes": notes,
    "preexisting_cases": preexisting_cases,
    "export_timestamp": datetime.now().isoformat()
}

output_path = "/tmp/fourth_amendment_brief_result.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Results written to {output_path}")
print(f"Total items: {total_items}")
print(f"Parent collection exists: {parent_collection_exists}")
print(f"Favorable subcollection exists: {favorable_collection_exists}")
print(f"Adverse subcollection exists: {adverse_collection_exists}")
print(f"Favorable items: {len(favorable_items)}")
print(f"Adverse items: {len(adverse_items)}")
print(f"Notes found: {len(notes)}")
print(f"Pre-existing cases present: {preexisting_cases}")
conn.close()
PYEOF

chmod 666 /tmp/fourth_amendment_brief_result.json 2>/dev/null || true
echo "=== Export Complete ==="
