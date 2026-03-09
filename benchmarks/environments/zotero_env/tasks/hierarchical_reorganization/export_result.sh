#!/bin/bash
# Export result for hierarchical_reorganization task

echo "=== Exporting hierarchical_reorganization result ==="

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

sleep 2

python3 << 'PYEOF'
import sqlite3
import json

DB = "/home/ga/Zotero/zotero.sqlite"

SUBCOLL_NAMES = ["Pre-1960", "1960-1999", "2000-2010", "Post-2010"]
PARENT_NAME = "Research Archive"
SOURCE_NAME = "Unsorted Import"

result = {
    "parent_collection_exists": False,
    "parent_collection_id": None,
    "subcollections": {},   # name -> {exists, id, paper_titles, count}
    "source_collection_deleted": True,
    "papers_in_wrong_bucket": [],
    "total_organized": 0,
}

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    # Check if source collection still exists
    cur.execute(
        "SELECT collectionID FROM collections WHERE collectionName=? AND libraryID=1",
        (SOURCE_NAME,)
    )
    row = cur.fetchone()
    result["source_collection_deleted"] = (row is None)

    # Check parent collection
    cur.execute(
        "SELECT collectionID FROM collections WHERE collectionName=? AND libraryID=1 AND parentCollectionID IS NULL",
        (PARENT_NAME,)
    )
    row = cur.fetchone()
    if row:
        result["parent_collection_exists"] = True
        result["parent_collection_id"] = row[0]
        parent_id = row[0]

        # Check each subcollection
        for subcoll_name in SUBCOLL_NAMES:
            cur.execute(
                "SELECT collectionID FROM collections WHERE collectionName=? AND parentCollectionID=? AND libraryID=1",
                (subcoll_name, parent_id)
            )
            row = cur.fetchone()
            if row:
                coll_id = row[0]
                cur.execute(
                    """SELECT v.value, d2.value as year
                       FROM collectionItems ci
                       JOIN items i ON ci.itemID=i.itemID
                       JOIN itemData d ON i.itemID=d.itemID
                       JOIN itemDataValues v ON d.valueID=v.valueID
                       LEFT JOIN (
                         SELECT itemID, v2.value FROM itemData d2
                         JOIN itemDataValues v2 ON d2.valueID=v2.valueID
                         WHERE d2.fieldID=6
                       ) d2 ON i.itemID=d2.itemID
                       WHERE ci.collectionID=? AND d.fieldID=1
                       AND i.itemID NOT IN (SELECT itemID FROM deletedItems)""",
                    (coll_id,)
                )
                rows = cur.fetchall()

                # Re-query properly
                cur.execute(
                    """SELECT i.itemID FROM collectionItems ci
                       JOIN items i ON ci.itemID=i.itemID
                       WHERE ci.collectionID=?
                       AND i.itemID NOT IN (SELECT itemID FROM deletedItems)""",
                    (coll_id,)
                )
                item_ids = [r[0] for r in cur.fetchall()]

                papers = []
                for iid in item_ids:
                    cur.execute(
                        """SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID
                           WHERE d.itemID=? AND d.fieldID=1""", (iid,))
                    title_row = cur.fetchone()
                    cur.execute(
                        """SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID
                           WHERE d.itemID=? AND d.fieldID=6""", (iid,))
                    year_row = cur.fetchone()
                    if title_row:
                        papers.append({
                            "title": title_row[0],
                            "year": year_row[0] if year_row else None
                        })

                result["subcollections"][subcoll_name] = {
                    "exists": True,
                    "id": coll_id,
                    "count": len(papers),
                    "papers": papers,
                }
                result["total_organized"] += len(papers)

                # Check for misplaced papers
                for p in papers:
                    if p["year"]:
                        yr = int(p["year"])
                        expected = None
                        if yr < 1960:
                            expected = "Pre-1960"
                        elif yr <= 1999:
                            expected = "1960-1999"
                        elif yr <= 2010:
                            expected = "2000-2010"
                        else:
                            expected = "Post-2010"
                        if expected and expected != subcoll_name:
                            result["papers_in_wrong_bucket"].append({
                                "title": p["title"],
                                "year": p["year"],
                                "placed_in": subcoll_name,
                                "should_be_in": expected
                            })
            else:
                result["subcollections"][subcoll_name] = {"exists": False, "count": 0, "papers": []}

    conn.close()

except Exception as e:
    result["db_error"] = str(e)
    import traceback
    result["traceback"] = traceback.format_exc()

with open("/tmp/hierarchical_reorganization_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Parent collection '{PARENT_NAME}' exists: {result['parent_collection_exists']}")
for name, info in result["subcollections"].items():
    print(f"  {name}: {info.get('count',0)} papers")
print(f"Source '{SOURCE_NAME}' deleted: {result['source_collection_deleted']}")
print(f"Papers in wrong bucket: {len(result['papers_in_wrong_bucket'])}")
PYEOF

echo "=== Export Complete: hierarchical_reorganization ==="
