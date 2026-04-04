#!/bin/bash
# Export result for correct_paper_year task

echo "=== Exporting correct_paper_year result ==="

DB="/home/ga/Zotero/zotero.sqlite"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

sleep 2

python3 << 'PYEOF'
import sqlite3
import json

DB = "/home/ga/Zotero/zotero.sqlite"

EINSTEIN_TITLE = "On the Electrodynamics of Moving Bodies"
SHANNON_TITLE = "A Mathematical Theory of Communication"

result = {
    "einstein_title": EINSTEIN_TITLE,
    "einstein_current_year": None,
    "einstein_correct": False,
    "shannon_title": SHANNON_TITLE,
    "shannon_current_year": None,
    "shannon_correct": False,
}

def get_paper_year(cur, title):
    """Get the date/year field for a paper with the given title."""
    cur.execute("""
        SELECT v.value
        FROM items i
        JOIN itemData dt ON i.itemID = dt.itemID AND dt.fieldID = 1
        JOIN itemDataValues vt ON dt.valueID = vt.valueID AND vt.value = ?
        JOIN itemData d ON i.itemID = d.itemID AND d.fieldID = 6
        JOIN itemDataValues v ON d.valueID = v.valueID
    """, (title,))
    row = cur.fetchone()
    return row[0] if row else None

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    einstein_year = get_paper_year(cur, EINSTEIN_TITLE)
    shannon_year = get_paper_year(cur, SHANNON_TITLE)

    result["einstein_current_year"] = einstein_year
    result["shannon_current_year"] = shannon_year

    # Check correctness: year must contain "1905" or "1948"
    # Zotero might store "1905", "1905-01-01", etc.
    if einstein_year:
        result["einstein_correct"] = "1905" in str(einstein_year)
    if shannon_year:
        result["shannon_correct"] = "1948" in str(shannon_year)

    conn.close()
except Exception as e:
    result["error"] = str(e)

with open("/tmp/correct_paper_year_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Einstein year: {result['einstein_current_year']} — correct: {result['einstein_correct']}")
print(f"Shannon year:  {result['shannon_current_year']} — correct: {result['shannon_correct']}")
PYEOF

echo "=== Export Complete: correct_paper_year ==="
