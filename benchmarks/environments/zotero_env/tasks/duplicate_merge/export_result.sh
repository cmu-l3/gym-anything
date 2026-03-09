#!/bin/bash
# Export result for duplicate_merge task

echo "=== Exporting duplicate_merge result ==="

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

sleep 3

python3 << 'PYEOF'
import sqlite3
import json

DB = "/home/ga/Zotero/zotero.sqlite"

EXPECTED_TITLES = [
    "Synaptic Plasticity and Memory: An Evaluation of the Hypothesis",
    "The Role of Dopamine in Reward and Motivation",
    "Grid Cells and the Entorhinal Map of Space",
    "Hebbian Synapses: Biophysical Mechanisms and Algorithms",
    "Default Mode Network Activity and Consciousness",
    "Mirror Neurons and the Simulation Theory of Mind-Reading",
    "Prefrontal Cortex and Executive Function: A Review",
    "Cortical Oscillations and the Binding Problem",
    "Neural Basis of Visual Attention",
    "Basal Ganglia and the Control of Action Selection",
]

result = {
    "current_item_count": 0,
    "items_by_title": {},   # title -> [itemIDs] (after merge should be exactly 1)
    "notes_by_title": {},   # title -> note_count
    "duplicate_titles": [],  # titles that still have >1 copy
    "notes_preserved": {},   # title -> bool (has at least 1 note)
    "total_notes": 0,
}

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    # Current item count (non-deleted journal articles)
    cur.execute(
        "SELECT COUNT(*) FROM items WHERE itemTypeID=22 AND itemID NOT IN (SELECT itemID FROM deletedItems)"
    )
    result["current_item_count"] = cur.fetchone()[0]

    # For each expected title, find all non-deleted copies
    for title in EXPECTED_TITLES:
        cur.execute(
            """SELECT i.itemID FROM items i
               JOIN itemData d ON i.itemID=d.itemID
               JOIN itemDataValues v ON d.valueID=v.valueID
               WHERE d.fieldID=1 AND v.value=?
               AND i.itemID NOT IN (SELECT itemID FROM deletedItems)""",
            (title,)
        )
        item_ids = [row[0] for row in cur.fetchall()]
        result["items_by_title"][title] = item_ids

        if len(item_ids) > 1:
            result["duplicate_titles"].append(title)

        # Count notes across all surviving copies
        total_notes = 0
        for iid in item_ids:
            cur.execute("SELECT COUNT(*) FROM itemNotes WHERE parentItemID=?", (iid,))
            total_notes += cur.fetchone()[0]
        result["notes_by_title"][title] = total_notes
        result["notes_preserved"][title] = total_notes > 0

    # Total note count
    cur.execute("SELECT COUNT(*) FROM itemNotes")
    result["total_notes"] = cur.fetchone()[0]

    conn.close()

except Exception as e:
    result["db_error"] = str(e)

with open("/tmp/duplicate_merge_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Current item count: {result['current_item_count']} (expect ~10)")
print(f"Remaining duplicates: {len(result['duplicate_titles'])}")
print(f"Papers with notes preserved: {sum(1 for v in result['notes_preserved'].values() if v)}/10")
PYEOF

echo "=== Export Complete: duplicate_merge ==="
