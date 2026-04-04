#!/bin/bash
# Export result for metadata_audit task

echo "=== Exporting metadata_audit result ==="

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

sleep 2

python3 << 'PYEOF'
import sqlite3
import json

DB = "/home/ga/Zotero/zotero.sqlite"

# Papers that had year errors: title -> (wrong_year, correct_year)
YEAR_ERROR_PAPERS = {
    "Caspase Activation Mechanisms in Apoptotic Cell Death": ("1988", "1998"),
    "RNA Interference: Gene Silencing by Double-Stranded RNA": ("1988", "1998"),
    "CRISPR-Cas9-Mediated Genome Editing in Human Cells": ("2003", "2013"),
    "Stem Cell-Derived Cerebral Organoids Model Human Brain Development": ("2003", "2013"),
    "Single-Cell RNA Sequencing Reveals Transcriptional Heterogeneity": ("2005", "2015"),
}

# Papers that had swapped names: title -> (wrong_first, correct_first, correct_last)
NAME_ERROR_PAPERS = {
    "Molecular Mechanisms of Synaptic Vesicle Endocytosis":
        ("Bhaskara", "Elena", "Bhaskara"),
    "Chromatin Remodeling Complexes and Gene Regulation":
        ("Peterson", "Craig L.", "Peterson"),
    "Insulin Signaling and the Regulation of Glucose Metabolism":
        ("Saltiel", "Alan R.", "Saltiel"),
    "The Role of MicroRNAs in Cancer Biology":
        ("Calin", "George A.", "Calin"),
    "Autophagy: Cellular and Molecular Mechanisms":
        ("Mizushima", "Noboru", "Mizushima"),
}

ABSTRACT_PLACEHOLDER_TITLES = [
    "Telomere Dynamics and Cellular Senescence",
    "Mechanisms of Antibiotic Resistance in Gram-Negative Bacteria",
    "The Gut Microbiome and Human Health",
    "Immune Checkpoint Blockade in Cancer Therapy",
    "Protein Structure Prediction Using Deep Learning",
]

result = {
    "year_errors": {},    # title -> {"stored_year": ..., "wrong_year": ..., "correct_year": ..., "fixed": bool}
    "name_errors": {},    # title -> {"current_first": ..., "wrong_first": ..., "fixed": bool}
    "abstract_placeholders": {},  # title -> {"current_abstract": ..., "fixed": bool}
}

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    def get_item_id(title):
        cur.execute(
            """SELECT i.itemID FROM items i
               JOIN itemData d ON i.itemID=d.itemID
               JOIN itemDataValues v ON d.valueID=v.valueID
               WHERE d.fieldID=1 AND v.value=?
               AND i.itemID NOT IN (SELECT itemID FROM deletedItems)""",
            (title,)
        )
        row = cur.fetchone()
        return row[0] if row else None

    def get_field(item_id, field_id):
        cur.execute(
            """SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID
               WHERE d.itemID=? AND d.fieldID=?""",
            (item_id, field_id)
        )
        row = cur.fetchone()
        return row[0] if row else None

    def get_first_author_names(item_id):
        cur.execute(
            """SELECT c.firstName, c.lastName FROM itemCreators ic
               JOIN creators c ON ic.creatorID=c.creatorID
               WHERE ic.itemID=? AND ic.orderIndex=0""",
            (item_id,)
        )
        row = cur.fetchone()
        return (row[0], row[1]) if row else (None, None)

    # Check year errors
    for title, (wrong_year, correct_year) in YEAR_ERROR_PAPERS.items():
        item_id = get_item_id(title)
        if item_id:
            current_year = get_field(item_id, 6)  # fieldID=6 is date
            result["year_errors"][title] = {
                "item_id": item_id,
                "stored_year": current_year,
                "wrong_year": wrong_year,
                "correct_year": correct_year,
                "fixed": current_year != wrong_year,
                "correct": current_year == correct_year,
            }

    # Check name errors
    for title, (wrong_first, correct_first, correct_last) in NAME_ERROR_PAPERS.items():
        item_id = get_item_id(title)
        if item_id:
            first, last = get_first_author_names(item_id)
            result["name_errors"][title] = {
                "item_id": item_id,
                "current_first": first,
                "current_last": last,
                "wrong_first": wrong_first,
                "correct_first": correct_first,
                "correct_last": correct_last,
                "fixed": first != wrong_first,
                "correct": first == correct_first and last == correct_last,
            }

    # Check abstract placeholders
    for title in ABSTRACT_PLACEHOLDER_TITLES:
        item_id = get_item_id(title)
        if item_id:
            abstract = get_field(item_id, 2)  # fieldID=2 is abstractNote
            is_placeholder = abstract == "Abstract not available" if abstract else False
            result["abstract_placeholders"][title] = {
                "item_id": item_id,
                "current_abstract": abstract[:200] if abstract else None,
                "fixed": not is_placeholder,
            }

    conn.close()

except Exception as e:
    result["db_error"] = str(e)
    import traceback
    result["traceback"] = traceback.format_exc()

with open("/tmp/metadata_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

year_fixed = sum(1 for v in result["year_errors"].values() if v.get("fixed"))
name_fixed = sum(1 for v in result["name_errors"].values() if v.get("fixed"))
abstract_fixed = sum(1 for v in result["abstract_placeholders"].values() if v.get("fixed"))
print(f"Year errors fixed: {year_fixed}/5")
print(f"Name errors fixed: {name_fixed}/5")
print(f"Abstract placeholders fixed: {abstract_fixed}/5")
PYEOF

echo "=== Export Complete: metadata_audit ==="
