#!/bin/bash
# Export result for group_papers_by_journal task

echo "=== Exporting group_papers_by_journal result ==="

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to robustly query SQLite and generate JSON result
python3 << 'PYEOF'
import sqlite3
import json
import os

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
RESULT_PATH = "/tmp/task_result.json"

# Expected target titles (normalized for partial matching if strictly needed, but exact is better)
# Note: Zotero stores publication names in 'publicationTitle' field (fieldID usually 38)
# We need to check which items are in the created collections.

result = {
    "nature_collection_exists": False,
    "neurips_collection_exists": False,
    "nature_papers_found": [],
    "neurips_papers_found": [],
    "nature_papers_wrong": [],
    "neurips_papers_wrong": [],
    "collections_created_timestamp": None
}

try:
    if not os.path.exists(DB_PATH):
        raise FileNotFoundError(f"Database not found at {DB_PATH}")

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # 1. Find Collections
    cur.execute("SELECT collectionID, collectionName FROM collections WHERE libraryID=1")
    collections = {row[1]: row[0] for row in cur.fetchall()}

    nature_id = collections.get("Nature Papers")
    neurips_id = collections.get("NeurIPS Papers")

    result["nature_collection_exists"] = (nature_id is not None)
    result["neurips_collection_exists"] = (neurips_id is not None)

    # Helper to get items in a collection with their Publication Title
    def get_collection_items_metadata(collection_id):
        if collection_id is None:
            return []
        
        # Join items -> itemData -> itemDataValues to get Publication Title (fieldID 38 usually, or check name)
        # However, paper title is fieldID 1 (title). We want to verify the PAPER TITLE to match expectations
        # AND check the PUBLICATION TITLE to see if it was a correct placement logic.
        
        # Let's pull Title (1) and Publication Title (38 usually, but let's look it up)
        
        # First find field ID for 'publicationTitle'
        cur.execute("SELECT fieldID FROM fields WHERE fieldName='publicationTitle'")
        res = cur.fetchone()
        pub_field_id = res[0] if res else 38
        
        # Find field ID for 'title'
        cur.execute("SELECT fieldID FROM fields WHERE fieldName='title'")
        res = cur.fetchone()
        title_field_id = res[0] if res else 1

        query = f"""
            SELECT 
                i.itemID,
                (SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.itemID=i.itemID AND d.fieldID={title_field_id}) as title,
                (SELECT v.value FROM itemData d JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.itemID=i.itemID AND d.fieldID={pub_field_id}) as publication
            FROM collectionItems ci
            JOIN items i ON ci.itemID = i.itemID
            WHERE ci.collectionID = ?
        """
        cur.execute(query, (collection_id,))
        return [{"id": r[0], "title": r[1], "publication": r[2]} for r in cur.fetchall()]

    # 2. Check Nature Collection
    if nature_id:
        items = get_collection_items_metadata(nature_id)
        for item in items:
            pub = (item["publication"] or "").strip()
            # Loose match for "Nature" but exclude "Nature [Something]" if strictly "Nature" is required
            # The prompt asks for papers published in 'Nature'.
            if pub == "Nature":
                result["nature_papers_found"].append(item["title"])
            else:
                result["nature_papers_wrong"].append({"title": item["title"], "pub": pub})

    # 3. Check NeurIPS Collection
    if neurips_id:
        items = get_collection_items_metadata(neurips_id)
        for item in items:
            pub = (item["publication"] or "").strip()
            if "Advances in Neural Information Processing Systems" in pub:
                result["neurips_papers_found"].append(item["title"])
            else:
                result["neurips_papers_wrong"].append({"title": item["title"], "pub": pub})

    conn.close()

except Exception as e:
    result["error"] = str(e)

# Write result
with open(RESULT_PATH, 'w') as f:
    json.dump(result, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete."
cat /tmp/task_result.json