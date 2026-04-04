#!/bin/bash
# Export result for citation_qa_export task

echo "=== Exporting citation_qa_export result ==="

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

sleep 2

python3 << 'PYEOF'
import sqlite3
import json
import os
import re

DB = "/home/ga/Zotero/zotero.sqlite"
BIB_PATH = "/home/ga/Desktop/references.bib"

EXPECTED_EMPTY_JOURNAL_TITLES = [
    "Algebraic Complexity Theory and Circuit Lower Bounds",
    "Interactive Proofs and Zero-Knowledge Arguments",
    "Parameterized Complexity and Kernelization",
]
EXPECTED_DUPLICATE_TITLES = [
    "Linear Programming and Extensions",
    "Computability and Unsolvability",
    "Foundations of Cryptography: Basic Tools",
]

result = {
    "cite_in_paper_item_count": 0,
    "cite_in_paper_titles": [],
    "duplicate_title_counts": {},   # title -> count of remaining items
    "empty_journal_status": {},     # title -> {"has_journal": bool, "journal_value": str}
    "bib_file_exists": False,
    "bib_file_size": 0,
    "bib_entry_count": 0,
    "bib_has_duplicates": False,
    "bib_duplicate_keys": [],
    "bib_entries_with_empty_journal": 0,
}

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    # Get all non-deleted items tagged "cite-in-paper"
    cur.execute("""
        SELECT i.itemID,
               (SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID
                WHERE d.itemID=i.itemID AND d.fieldID=1 LIMIT 1) as title
        FROM items i
        JOIN itemTags it ON i.itemID=it.itemID
        JOIN tags t ON it.tagID=t.tagID
        WHERE t.name='cite-in-paper'
          AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    """)
    cite_items = cur.fetchall()
    result["cite_in_paper_item_count"] = len(cite_items)
    result["cite_in_paper_titles"] = [row[1] for row in cite_items if row[1]]

    # Check for remaining duplicate titles among cite-in-paper items
    from collections import Counter
    title_counts = Counter(result["cite_in_paper_titles"])
    for title in EXPECTED_DUPLICATE_TITLES:
        result["duplicate_title_counts"][title] = title_counts.get(title, 0)

    # Check journal field for papers that had empty journals
    for title in EXPECTED_EMPTY_JOURNAL_TITLES:
        cur.execute(
            """SELECT i.itemID FROM items i
               JOIN itemData d ON i.itemID=d.itemID
               JOIN itemDataValues v ON d.valueID=v.valueID
               WHERE d.fieldID=1 AND v.value=?
               AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
               LIMIT 1""",
            (title,)
        )
        row = cur.fetchone()
        if row:
            item_id = row[0]
            cur.execute(
                """SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID
                   WHERE d.itemID=? AND d.fieldID=38""",
                (item_id,)
            )
            journal_row = cur.fetchone()
            journal = journal_row[0] if journal_row else None
            result["empty_journal_status"][title] = {
                "has_journal": bool(journal and journal.strip()),
                "journal_value": journal,
            }

    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# Parse BibTeX file
if os.path.exists(BIB_PATH):
    result["bib_file_exists"] = True
    result["bib_file_size"] = os.path.getsize(BIB_PATH)
    try:
        with open(BIB_PATH, "r", errors="replace") as f:
            content = f.read()

        # Count entries
        entries = re.findall(r'@\w+\s*\{', content)
        result["bib_entry_count"] = len(entries)

        # Check for duplicate citekeys
        citekeys = re.findall(r'@\w+\s*\{([^,]+),', content)
        key_counts = Counter(citekeys)
        dup_keys = [k for k, c in key_counts.items() if c > 1]
        result["bib_has_duplicates"] = len(dup_keys) > 0
        result["bib_duplicate_keys"] = dup_keys

        # Check for entries missing journal field
        # Split into entry blocks
        entry_blocks = re.split(r'(?=@\w+\s*\{)', content)
        empty_journal_count = 0
        for block in entry_blocks:
            if not block.strip():
                continue
            if re.search(r'@article', block, re.IGNORECASE):
                if not re.search(r'journal\s*=\s*\{[^}]+\}', block, re.IGNORECASE):
                    empty_journal_count += 1
        result["bib_entries_with_empty_journal"] = empty_journal_count

    except Exception as e:
        result["bib_parse_error"] = str(e)

with open("/tmp/citation_qa_export_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"cite-in-paper items: {result['cite_in_paper_item_count']}")
print(f"Remaining duplicates: {result['duplicate_title_counts']}")
print(f"Empty journal status: {result['empty_journal_status']}")
print(f"BibTeX file: exists={result['bib_file_exists']}, entries={result['bib_entry_count']}")
print(f"BibTeX duplicate keys: {result['bib_duplicate_keys']}")
PYEOF

echo "=== Export Complete: citation_qa_export ==="
