#!/bin/bash

echo "=== Exporting citation_audit_repair results ==="

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

# Query all user library cases with their field values
c.execute("""
SELECT
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=58),'') as caseName,
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=60),'') as court,
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=49),'') as reporter,
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=67),'') as firstPage,
  COALESCE((SELECT idv.value FROM itemData id JOIN itemDataValues idv ON id.valueID=idv.valueID WHERE id.itemID=i.itemID AND id.fieldID=69),'') as dateDecided
FROM items i
WHERE i.libraryID=1 AND i.itemTypeID NOT IN (1,3,31)
""")
all_cases = [dict(row) for row in c.fetchall()]

# Count items with 'audited' tag
c.execute("""
SELECT COUNT(DISTINCT it.itemID)
FROM itemTags it
JOIN tags t ON it.tagID=t.tagID
WHERE t.name='audited' AND it.itemID IN (SELECT itemID FROM items WHERE libraryID=1)
""")
audited_tag_count = c.fetchone()[0]

# Check for 'Audited Cases' collection
c.execute("""
SELECT collectionID FROM collections
WHERE collectionName='Audited Cases' AND libraryID=1
""")
audited_col_row = c.fetchone()
audited_collection_exists = audited_col_row is not None

audited_collection_item_count = 0
if audited_collection_exists:
    col_id = audited_col_row[0]
    c.execute("SELECT COUNT(*) FROM collectionItems WHERE collectionID=?", (col_id,))
    audited_collection_item_count = c.fetchone()[0]

# Total items in user library
c.execute("SELECT COUNT(*) FROM items WHERE libraryID=1 AND itemTypeID NOT IN (1,3,31)")
total_items = c.fetchone()[0]

result = {
    "all_cases": all_cases,
    "audited_tag_count": audited_tag_count,
    "audited_collection_exists": audited_collection_exists,
    "audited_collection_item_count": audited_collection_item_count,
    "total_items": total_items,
    "export_timestamp": datetime.now().isoformat()
}

output_path = "/tmp/citation_audit_repair_result.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Results written to {output_path}")
print(f"Total items: {total_items}")
print(f"Audited tag count: {audited_tag_count}")
print(f"Audited Cases collection exists: {audited_collection_exists}")
print(f"Audited Cases collection item count: {audited_collection_item_count}")
conn.close()
PYEOF

chmod 666 /tmp/citation_audit_repair_result.json 2>/dev/null || true
echo "=== Export Complete ==="
