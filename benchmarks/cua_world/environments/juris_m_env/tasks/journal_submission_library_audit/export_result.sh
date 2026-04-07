#!/bin/bash
echo "=== Exporting journal_submission_library_audit results ==="

# Find Jurism database
JURISM_DB=""
for db_candidate in /home/ga/Jurism/jurism.sqlite /home/ga/Jurism/zotero.sqlite; do
    if [ -f "$db_candidate" ]; then
        JURISM_DB="$db_candidate"
        break
    fi
done

if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Jurism database not found"
    cat > /tmp/journal_submission_library_audit_result.json << 'EOF'
{"error": "Jurism database not found", "passed": false}
EOF
    exit 1
fi

echo "Using database: $JURISM_DB"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/journal_submission_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/journal_submission_final.png 2>/dev/null || true
echo "Final screenshot saved"

# Kill Jurism to flush prefs.js to disk and release SQLite lock
pkill -f "/opt/jurism/jurism" 2>/dev/null || true
sleep 3
echo "Jurism stopped for database export"

python3 << PYEOF
import sqlite3, json, sys, os, glob, re
from datetime import datetime

JURISM_DB = "$JURISM_DB"

try:
    conn = sqlite3.connect(JURISM_DB)
    c = conn.cursor()
except Exception as e:
    result = {"error": str(e), "export_timestamp": datetime.now().isoformat()}
    with open("/tmp/journal_submission_library_audit_result.json", "w") as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

# =========================================================================
# 1. All items with their metadata fields
# =========================================================================
# Cases: caseName(58), court(60), reporter(49), reporterVolume(66), firstPage(67), dateDecided(69)
c.execute("""
SELECT
  i.itemID,
  i.itemTypeID,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=58),'') as caseName,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=60),'') as court,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=49),'') as reporter,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=66),'') as reporterVolume,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=67),'') as firstPage,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=69),'') as dateDecided,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=1),'') as title,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=7),'') as publicationTitle,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=22),'') as volume,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=47),'') as pages,
  COALESCE((SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=i.itemID AND id2.fieldID=8),'') as date
FROM items i
WHERE i.libraryID=1 AND i.itemTypeID NOT IN (1,3,31)
""")
all_items = []
for row in c.fetchall():
    all_items.append({
        "itemID": row[0],
        "itemTypeID": row[1],
        "caseName": row[2],
        "court": row[3],
        "reporter": row[4],
        "reporterVolume": row[5],
        "firstPage": row[6],
        "dateDecided": row[7],
        "title": row[8],
        "publicationTitle": row[9],
        "volume": row[10],
        "pages": row[11],
        "date": row[12],
        "displayName": row[2] if row[2] else row[8],
    })

total_items = len(all_items)

# =========================================================================
# 2. Collection hierarchy
# =========================================================================
def get_collection_id(conn, name, parent_id=None):
    c = conn.cursor()
    if parent_id is None:
        c.execute("SELECT collectionID FROM collections WHERE collectionName=? AND (parentCollectionID IS NULL OR parentCollectionID=0) AND libraryID=1", (name,))
    else:
        c.execute("SELECT collectionID FROM collections WHERE collectionName=? AND parentCollectionID=? AND libraryID=1", (name, parent_id))
    r = c.fetchone()
    return r[0] if r else None

parent_id = get_collection_id(conn, "Fourth Amendment Digital Privacy")
parent_collection_exists = parent_id is not None

subcollection_names = ["Foundational Precedent", "Digital Privacy Doctrine", "Scholarly Analysis", "Limiting Authority"]
subcollections = {}
for name in subcollection_names:
    cid = get_collection_id(conn, name, parent_id) if parent_id else None
    subcollections[name] = {"exists": cid is not None, "id": cid}

def get_subcollection_items(conn, coll_id):
    if not coll_id:
        return []
    c = conn.cursor()
    c.execute("""
        SELECT COALESCE(
            (SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=ci.itemID AND id2.fieldID=58),
            (SELECT idv.value FROM itemData id2 JOIN itemDataValues idv ON id2.valueID=idv.valueID WHERE id2.itemID=ci.itemID AND id2.fieldID=1),
            'Unknown'
        ) FROM collectionItems ci WHERE ci.collectionID=?
    """, (coll_id,))
    return [r[0] for r in c.fetchall()]

collection_items = {}
for name in subcollection_names:
    cid = subcollections[name]["id"]
    collection_items[name] = get_subcollection_items(conn, cid)

# Total unique items assigned to any collection
c.execute("""
    SELECT COUNT(DISTINCT ci.itemID)
    FROM collectionItems ci
    JOIN collections col ON ci.collectionID=col.collectionID
    WHERE col.libraryID=1
""")
r = c.fetchone()
total_assigned_items = r[0] if r else 0

# =========================================================================
# 3. Related links
# =========================================================================
# Map items to (itemID, key) for relation checking
def find_item(conn, search_term, field_id=58):
    c = conn.cursor()
    c.execute("""
        SELECT i.itemID, i.key
        FROM items i
        JOIN itemData id ON i.itemID = id.itemID
        JOIN itemDataValues idv ON id.valueID = idv.valueID
        WHERE id.fieldID = ? AND idv.value LIKE ?
        LIMIT 1
    """, (field_id, f"%{search_term}%"))
    row = c.fetchone()
    return {"id": row[0], "key": row[1]} if row else None

def check_relation(conn, item1, item2):
    if not item1 or not item2:
        return {"forward": False, "reverse": False, "complete": False}
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM itemRelations WHERE itemID = ? AND object LIKE ?",
              (item1['id'], f"%{item2['key']}"))
    fwd = c.fetchone()[0] > 0
    c.execute("SELECT COUNT(*) FROM itemRelations WHERE itemID = ? AND object LIKE ?",
              (item2['id'], f"%{item1['key']}"))
    rev = c.fetchone()[0] > 0
    return {"forward": fwd, "reverse": rev, "complete": fwd and rev}

# Find items for relation pairs
carpenter = find_item(conn, "Carpenter", 58)
freiwald = find_item(conn, "Cell Phone Location", 1)
katz = find_item(conn, "Katz", 58)
kerr = find_item(conn, "Fourth Amendment and New Tech", 1)
smith = find_item(conn, "Smith v. Maryland", 58)
murphy = find_item(conn, "Case Against the Case", 1)
riley = find_item(conn, "Riley", 58)
tokson = find_item(conn, "Knowledge and Fourth", 1)

related_pairs = {
    "carpenter_freiwald": check_relation(conn, carpenter, freiwald),
    "katz_kerr": check_relation(conn, katz, kerr),
    "smith_murphy": check_relation(conn, smith, murphy),
    "riley_tokson": check_relation(conn, riley, tokson),
}

c.execute("SELECT COUNT(*) FROM itemRelations")
total_relations = c.fetchone()[0]

# =========================================================================
# 4. Quick Copy citation style from prefs.js
# =========================================================================
quick_copy_style = ""
prefs_files = (
    glob.glob('/home/ga/.zotero/zotero/*/prefs.js') +
    glob.glob('/home/ga/.jurism/jurism/*/prefs.js')
)
for pf in prefs_files:
    try:
        content = open(pf).read()
        m = re.search(r'quickCopy\.setting["\s,=]+["\']([^"\']+)["\']', content)
        if m:
            quick_copy_style = m.group(1)
            break
    except Exception:
        pass

# =========================================================================
# 5. RIS export file
# =========================================================================
ris_path = "/home/ga/Documents/symposium_bibliography.ris"
ris_exists = os.path.exists(ris_path)
ris_size = os.path.getsize(ris_path) if ris_exists else 0
ris_item_count = 0
if ris_exists:
    try:
        with open(ris_path) as f:
            ris_item_count = f.read().count("TY  -")
    except Exception:
        pass

conn.close()

# =========================================================================
# Assemble result
# =========================================================================
result = {
    "all_items": all_items,
    "total_items": total_items,
    "parent_collection_exists": parent_collection_exists,
    "subcollections": {name: subcollections[name]["exists"] for name in subcollection_names},
    "collection_items": collection_items,
    "total_assigned_items": total_assigned_items,
    "related_pairs": related_pairs,
    "total_relations": total_relations,
    "quick_copy_style": quick_copy_style,
    "ris_export": {
        "exists": ris_exists,
        "size_bytes": ris_size,
        "item_count": ris_item_count,
    },
    "export_timestamp": datetime.now().isoformat(),
}

output_path = "/tmp/journal_submission_library_audit_result.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Results written to {output_path}")
print(f"Total items: {total_items}")
print(f"Parent collection exists: {parent_collection_exists}")
print(f"Subcollections: {subcollections}")
print(f"Total assigned: {total_assigned_items}")
print(f"Related pairs: {related_pairs}")
print(f"Quick Copy style: {quick_copy_style}")
print(f"RIS export: exists={ris_exists}, size={ris_size}, items={ris_item_count}")
PYEOF

chmod 666 /tmp/journal_submission_library_audit_result.json 2>/dev/null || true
echo "=== Export Complete ==="
