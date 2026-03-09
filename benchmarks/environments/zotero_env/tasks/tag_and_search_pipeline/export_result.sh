#!/bin/bash
# Export result for tag_and_search_pipeline task

echo "=== Exporting tag_and_search_pipeline result ==="

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

sleep 2

python3 << 'PYEOF'
import sqlite3
import json
import os

DB = "/home/ga/Zotero/zotero.sqlite"

result = {
    "priority_paper_tags": {},   # title -> list of tag names
    "saved_search_exists": False,
    "saved_search_conditions": [],
    "bib_file_exists": False,
    "bib_file_size": 0,
    "bib_content_snippet": "",
    "review_now_items": [],      # titles of items tagged review-now
    "review_later_items": [],    # titles of items tagged review-later
}

BIB_PATH = "/home/ga/Desktop/review_now.bib"

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    # Get all priority-tagged items and their years and ALL tags
    cur.execute("""
        SELECT DISTINCT i.itemID,
               (SELECT v.value FROM itemData d2 JOIN itemDataValues v ON d2.valueID=v.valueID
                WHERE d2.itemID=i.itemID AND d2.fieldID=1 LIMIT 1) as title,
               (SELECT v.value FROM itemData d2 JOIN itemDataValues v ON d2.valueID=v.valueID
                WHERE d2.itemID=i.itemID AND d2.fieldID=6 LIMIT 1) as year
        FROM items i
        JOIN itemTags it ON i.itemID=it.itemID
        JOIN tags t ON it.tagID=t.tagID
        WHERE t.name='priority'
          AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    """)
    priority_items = cur.fetchall()

    for item_id, title, year in priority_items:
        if not title:
            continue
        cur.execute("""
            SELECT t.name FROM tags t
            JOIN itemTags it ON t.tagID=it.tagID
            WHERE it.itemID=?
        """, (item_id,))
        tags = [row[0] for row in cur.fetchall()]
        result["priority_paper_tags"][title] = tags

    # Get all items tagged "review-now"
    cur.execute("""
        SELECT v.value FROM items i
        JOIN itemData d ON i.itemID=d.itemID
        JOIN itemDataValues v ON d.valueID=v.valueID
        JOIN itemTags it ON i.itemID=it.itemID
        JOIN tags t ON it.tagID=t.tagID
        WHERE d.fieldID=1 AND t.name='review-now'
          AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    """)
    result["review_now_items"] = [row[0] for row in cur.fetchall()]

    # Get all items tagged "review-later"
    cur.execute("""
        SELECT v.value FROM items i
        JOIN itemData d ON i.itemID=d.itemID
        JOIN itemDataValues v ON d.valueID=v.valueID
        JOIN itemTags it ON i.itemID=it.itemID
        JOIN tags t ON it.tagID=t.tagID
        WHERE d.fieldID=1 AND t.name='review-later'
          AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    """)
    result["review_later_items"] = [row[0] for row in cur.fetchall()]

    # Check for saved search named "Review Now"
    cur.execute(
        "SELECT savedSearchID, savedSearchName FROM savedSearches WHERE savedSearchName='Review Now' AND libraryID=1"
    )
    row = cur.fetchone()
    if row:
        result["saved_search_exists"] = True
        ss_id = row[0]
        cur.execute(
            "SELECT condition, operator, value FROM savedSearchConditions WHERE savedSearchID=?",
            (ss_id,)
        )
        result["saved_search_conditions"] = [
            {"condition": r[0], "operator": r[1], "value": r[2]}
            for r in cur.fetchall()
        ]

    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# Check BibTeX file
if os.path.exists(BIB_PATH):
    result["bib_file_exists"] = True
    result["bib_file_size"] = os.path.getsize(BIB_PATH)
    try:
        with open(BIB_PATH, "r", errors="replace") as f:
            content = f.read()
        result["bib_content_snippet"] = content[:500]
        result["bib_entry_count"] = content.count("@article") + content.count("@inproceedings") + content.count("@book")
    except Exception as e:
        result["bib_read_error"] = str(e)

with open("/tmp/tag_and_search_pipeline_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Priority tags: {len(result['priority_paper_tags'])} items")
print(f"review-now items: {len(result['review_now_items'])}")
print(f"review-later items: {len(result['review_later_items'])}")
print(f"Saved search 'Review Now' exists: {result['saved_search_exists']}")
print(f"BibTeX file exists: {result['bib_file_exists']} (size: {result.get('bib_file_size',0)} bytes)")
PYEOF

echo "=== Export Complete: tag_and_search_pipeline ==="
