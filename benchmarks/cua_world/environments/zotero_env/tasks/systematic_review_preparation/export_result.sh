#!/bin/bash
# Export result for systematic_review_preparation task

echo "=== Exporting systematic_review_preparation result ==="

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

sleep 2

# Copy DB to avoid lock contention with running Zotero
cp /home/ga/Zotero/zotero.sqlite /tmp/zotero_export_sysrev.sqlite 2>/dev/null || true
sleep 1

python3 << 'PYEOF'
import sqlite3
import json
import os
import re
import shutil

DB = "/tmp/zotero_export_sysrev.sqlite"
DB_ORIG = "/home/ga/Zotero/zotero.sqlite"
BIB_PATH = "/home/ga/Desktop/included_studies.bib"

# Use copy if available, fall back to original with timeout
if not os.path.exists(DB):
    DB = DB_ORIG

PRE2000_TITLES = [
    "A Quantitative Description of Membrane Current and its Application to Conduction and Excitation in Nerve",
    "Neural Networks and Physical Systems with Emergent Collective Computational Abilities",
    "Learning Representations by Back-propagating Errors",
    "Receptive Fields, Binocular Interaction and Functional Architecture in the Cat's Visual Cortex",
]

INCOMPLETE_TITLES = [
    "Performance-optimized hierarchical models predict neural responses in higher visual cortex",
    "Vector-based navigation using grid-like representations in artificial agents",
    "A Task-Optimized Neural Network Replicates Human Auditory Behavior, Predicts Brain Responses, and Reveals a Cortical Processing Hierarchy",
    "If deep learning is the answer, what is the question?",
]

DUPLICATE_TITLES = [
    "Neuroscience-Inspired Artificial Intelligence",
    "A deep learning framework for neuroscience",
    "Toward an Integration of Deep Learning and Neuroscience",
]

VENUE_CHECK_PAPERS = {
    "Recurrent neural networks as versatile tools of neuroscience research": "Current Opinion in Neurobiology",
    "Deep Neural Networks: A New Framework for Modeling Biological Vision and Brain Information Processing": "Annual Review of Vision Science",
}

result = {
    "total_non_deleted_items": 0,
    "trashed_titles": [],
    "duplicate_title_counts": {},
    "incomplete_record_tagged_titles": [],
    "needs_manual_review_collection": {
        "exists": False,
        "item_count": 0,
        "titles": [],
    },
    "included_studies_collection": {
        "exists": False,
        "item_count": 0,
        "titles": [],
    },
    "venue_values": {},
    "screening_summary_note": {
        "exists": False,
        "content_snippet": "",
    },
    "bib_file_exists": False,
    "bib_file_size": 0,
    "bib_entry_count": 0,
}

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    # ── Total non-deleted journal articles ────────────────────────────────
    cur.execute("""
        SELECT COUNT(*) FROM items
        WHERE itemTypeID=22 AND itemID NOT IN (SELECT itemID FROM deletedItems)
    """)
    result["total_non_deleted_items"] = cur.fetchone()[0]

    # ── Trashed items (check for pre-2000 papers) ────────────────────────
    cur.execute("""
        SELECT v.value FROM items i
        JOIN deletedItems di ON i.itemID=di.itemID
        JOIN itemData d ON i.itemID=d.itemID
        JOIN itemDataValues v ON d.valueID=v.valueID
        WHERE d.fieldID=1
    """)
    result["trashed_titles"] = [row[0] for row in cur.fetchall()]

    # ── Duplicate title counts (check if duplicates were merged) ─────────
    from collections import Counter
    cur.execute("""
        SELECT v.value FROM items i
        JOIN itemData d ON i.itemID=d.itemID
        JOIN itemDataValues v ON d.valueID=v.valueID
        WHERE d.fieldID=1 AND i.itemTypeID=22
          AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    """)
    all_titles = [row[0] for row in cur.fetchall()]
    title_counts = Counter(all_titles)
    for title in DUPLICATE_TITLES:
        result["duplicate_title_counts"][title] = title_counts.get(title, 0)

    # ── Items tagged "incomplete-record" ─────────────────────────────────
    cur.execute("""
        SELECT v.value FROM items i
        JOIN itemData d ON i.itemID=d.itemID
        JOIN itemDataValues v ON d.valueID=v.valueID
        JOIN itemTags it ON i.itemID=it.itemID
        JOIN tags t ON it.tagID=t.tagID
        WHERE d.fieldID=1 AND t.name='incomplete-record'
          AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
    """)
    result["incomplete_record_tagged_titles"] = [row[0] for row in cur.fetchall()]

    # ── "Needs Manual Review" collection ─────────────────────────────────
    cur.execute("""
        SELECT collectionID FROM collections
        WHERE collectionName='Needs Manual Review' AND libraryID=1
    """)
    nmr_row = cur.fetchone()
    if nmr_row:
        nmr_id = nmr_row[0]
        result["needs_manual_review_collection"]["exists"] = True
        cur.execute("""
            SELECT v.value FROM collectionItems ci
            JOIN items i ON ci.itemID=i.itemID
            JOIN itemData d ON i.itemID=d.itemID
            JOIN itemDataValues v ON d.valueID=v.valueID
            WHERE ci.collectionID=? AND d.fieldID=1
              AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
        """, (nmr_id,))
        titles = [row[0] for row in cur.fetchall()]
        result["needs_manual_review_collection"]["item_count"] = len(titles)
        result["needs_manual_review_collection"]["titles"] = titles

    # ── "Included Studies" collection ────────────────────────────────────
    cur.execute("""
        SELECT collectionID FROM collections
        WHERE collectionName='Included Studies' AND libraryID=1
    """)
    is_row = cur.fetchone()
    if is_row:
        is_id = is_row[0]
        result["included_studies_collection"]["exists"] = True
        cur.execute("""
            SELECT v.value FROM collectionItems ci
            JOIN items i ON ci.itemID=i.itemID
            JOIN itemData d ON i.itemID=d.itemID
            JOIN itemDataValues v ON d.valueID=v.valueID
            WHERE ci.collectionID=? AND d.fieldID=1
              AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
        """, (is_id,))
        titles = [row[0] for row in cur.fetchall()]
        result["included_studies_collection"]["item_count"] = len(titles)
        result["included_studies_collection"]["titles"] = titles

        # ── Standalone note "Screening Summary" in Included Studies ───────
        cur.execute("""
            SELECT n.note FROM collectionItems ci
            JOIN items i ON ci.itemID=i.itemID
            JOIN itemNotes n ON i.itemID=n.itemID
            WHERE ci.collectionID=? AND i.itemTypeID=28
              AND n.parentItemID IS NULL
              AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
        """, (is_id,))
        for (note_content,) in cur.fetchall():
            if note_content and "Screening Summary" in note_content:
                result["screening_summary_note"]["exists"] = True
                result["screening_summary_note"]["content_snippet"] = note_content[:500]
                break

    # ── Venue values for papers that needed fixing ───────────────────────
    for title, expected_venue in VENUE_CHECK_PAPERS.items():
        cur.execute("""
            SELECT i.itemID FROM items i
            JOIN itemData d ON i.itemID=d.itemID
            JOIN itemDataValues v ON d.valueID=v.valueID
            WHERE d.fieldID=1 AND v.value=?
              AND i.itemID NOT IN (SELECT itemID FROM deletedItems)
            LIMIT 1
        """, (title,))
        row = cur.fetchone()
        if row:
            item_id = row[0]
            cur.execute("""
                SELECT v.value FROM itemData d
                JOIN itemDataValues v ON d.valueID=v.valueID
                WHERE d.itemID=? AND d.fieldID=38
            """, (item_id,))
            venue_row = cur.fetchone()
            result["venue_values"][title] = venue_row[0] if venue_row else None

    conn.close()

except Exception as e:
    result["db_error"] = str(e)

# ── Parse BibTeX file ────────────────────────────────────────────────────
if os.path.exists(BIB_PATH):
    result["bib_file_exists"] = True
    result["bib_file_size"] = os.path.getsize(BIB_PATH)
    try:
        with open(BIB_PATH, "r", errors="replace") as f:
            content = f.read()
        entries = re.findall(r'@\w+\s*\{', content)
        result["bib_entry_count"] = len(entries)
    except Exception as e:
        result["bib_parse_error"] = str(e)

with open("/tmp/systematic_review_preparation_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Non-deleted items: {result['total_non_deleted_items']}")
print(f"Trashed: {len(result['trashed_titles'])} items")
print(f"Duplicate title counts: {result['duplicate_title_counts']}")
print(f"Tagged incomplete-record: {len(result['incomplete_record_tagged_titles'])}")
print(f"Needs Manual Review: exists={result['needs_manual_review_collection']['exists']}, count={result['needs_manual_review_collection']['item_count']}")
print(f"Included Studies: exists={result['included_studies_collection']['exists']}, count={result['included_studies_collection']['item_count']}")
print(f"Venue values: {result['venue_values']}")
print(f"Screening note: exists={result['screening_summary_note']['exists']}")
print(f"BibTeX: exists={result['bib_file_exists']}, entries={result['bib_entry_count']}")
PYEOF

echo "=== Export Complete: systematic_review_preparation ==="
