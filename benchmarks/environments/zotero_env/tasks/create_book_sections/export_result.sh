#!/bin/bash
echo "=== Exporting create_book_sections results ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Wait a moment for DB writes
sleep 2

# Python script to analyze the complex relationships (Items -> Data -> Creators)
python3 << 'PYEOF'
import sqlite3
import json
import os

db_path = "/home/ga/Zotero/zotero.sqlite"
output_path = "/tmp/task_result.json"

result = {
    "parent_is_book": False,
    "weaver_section_found": False,
    "weaver_pages_correct": False,
    "weaver_author_correct": False,
    "shannon_section_found": False,
    "shannon_pages_correct": False,
    "shannon_author_correct": False,
    "items_created_during_task": 0
}

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # 1. Check Parent Item ("The Mathematical Theory of Communication", year 1949)
    # Item type 2 = Book
    cur.execute("""
        SELECT i.itemTypeID
        FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE d.fieldID = 1 -- Title
          AND v.value = 'The Mathematical Theory of Communication'
          AND i.itemTypeID = 2
    """)
    if cur.fetchone():
        result["parent_is_book"] = True

    # Helper function to find an item by title, type, and check fields
    def check_item(title_fragment, target_author_last, target_pages):
        # Find potential item IDs matching title and Type=3 (Book Section)
        query = """
            SELECT i.itemID
            FROM items i
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE i.itemTypeID = 3
              AND v.value LIKE ?
              AND d.fieldID = 1 -- Title
        """
        cur.execute(query, (f"%{title_fragment}%",))
        candidates = cur.fetchall()

        item_status = {
            "found": False,
            "pages": False,
            "author": False
        }

        for (item_id,) in candidates:
            item_status["found"] = True

            # Check Pages (fieldID 32 usually, but might vary, let's query value)
            # In Zotero 7/Standard: Pages field
            cur.execute("""
                SELECT v.value
                FROM itemData d
                JOIN itemDataValues v ON d.valueID = v.valueID
                WHERE d.itemID = ? AND d.fieldID = 32
            """, (item_id,))
            page_row = cur.fetchone()
            if page_row and page_row[0] == target_pages:
                item_status["pages"] = True

            # Check Authors
            # Get creators for this item
            cur.execute("""
                SELECT c.lastName
                FROM itemCreators ic
                JOIN creators c ON ic.creatorID = c.creatorID
                WHERE ic.itemID = ?
            """, (item_id,))
            creators = [r[0] for r in cur.fetchall()]

            # Strictly check that ONLY the target author is present (or at least present)
            # Task asks to remove the other author.
            if target_author_last in creators and len(creators) == 1:
                item_status["author"] = True
            elif target_author_last in creators:
                # Partial credit logic handled in verifier if needed, simple check here
                pass

            if item_status["found"] and item_status["pages"] and item_status["author"]:
                return item_status # Perfect match found

        return item_status

    # 2. Check Weaver Section
    # Title: "Recent Contributions..."
    w_stats = check_item("Recent Contributions", "Weaver", "1-28")
    result["weaver_section_found"] = w_stats["found"]
    result["weaver_pages_correct"] = w_stats["pages"]
    result["weaver_author_correct"] = w_stats["author"]

    # 3. Check Shannon Section
    # Title: "The Mathematical Theory of Communication" (Same as book, but Section type)
    # Note: Search specific title to differentiate from book
    s_stats = check_item("The Mathematical Theory of Communication", "Shannon", "29-125")
    result["shannon_section_found"] = s_stats["found"]
    result["shannon_pages_correct"] = s_stats["pages"]
    result["shannon_author_correct"] = s_stats["author"]

    # 4. Check for newly created items (Anti-gaming/Activity check)
    # We can check dateAdded, but sqlite time string format varies.
    # Alternatively, check if total items > initial.
    # We'll just rely on the specific checks above primarily.

    conn.close()

except Exception as e:
    result["error"] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to safe location
cp /tmp/task_result.json /tmp/safe_task_result.json 2>/dev/null
chmod 666 /tmp/safe_task_result.json

echo "=== Export complete ==="