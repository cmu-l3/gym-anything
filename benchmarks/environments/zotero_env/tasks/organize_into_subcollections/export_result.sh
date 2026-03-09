#!/bin/bash
# Export result for organize_into_subcollections task

echo "=== Exporting organize_into_subcollections result ==="

DB="/home/ga/Zotero/zotero.sqlite"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

sleep 2

python3 << 'PYEOF'
import sqlite3
import json

DB = "/home/ga/Zotero/zotero.sqlite"

# Required paper titles for each subcollection
NLP_TITLES = [
    "Attention Is All You Need",
    "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding",
    "Language Models are Few-Shot Learners",
]
VISION_TITLES = [
    "ImageNet Classification with Deep Convolutional Neural Networks",
    "Deep Residual Learning for Image Recognition",
    "Generative Adversarial Nets",
]

result = {
    "parent_collection_found": False,
    "parent_collection_id": None,
    "nlp_subcollection_found": False,
    "nlp_subcollection_id": None,
    "vision_subcollection_found": False,
    "vision_subcollection_id": None,
    "nlp_papers_present": [],
    "nlp_papers_missing": [],
    "vision_papers_present": [],
    "vision_papers_missing": [],
    "nlp_paper_count": 0,
    "vision_paper_count": 0,
    "all_collections": [],
}

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    # Get all collections
    cur.execute("SELECT collectionID, collectionName, parentCollectionID FROM collections WHERE libraryID=1")
    all_cols = cur.fetchall()
    result["all_collections"] = [
        {"id": r[0], "name": r[1], "parent_id": r[2]} for r in all_cols
    ]

    # Find "Deep Learning Survey"
    parent = next((r for r in all_cols if r[1] == "Deep Learning Survey"), None)
    if parent:
        result["parent_collection_found"] = True
        result["parent_collection_id"] = parent[0]
        parent_id = parent[0]

        # Find "NLP Papers" as child of parent
        nlp = next((r for r in all_cols if r[1] == "NLP Papers" and r[2] == parent_id), None)
        if nlp:
            result["nlp_subcollection_found"] = True
            result["nlp_subcollection_id"] = nlp[0]

        # Find "Vision Papers" as child of parent
        vis = next((r for r in all_cols if r[1] == "Vision Papers" and r[2] == parent_id), None)
        if vis:
            result["vision_subcollection_found"] = True
            result["vision_subcollection_id"] = vis[0]

    def get_titles_in_collection(col_id):
        if col_id is None:
            return []
        cur.execute("""
            SELECT v.value FROM collectionItems ci
            JOIN items i ON ci.itemID = i.itemID
            JOIN itemData d ON i.itemID = d.itemID AND d.fieldID = 1
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE ci.collectionID = ?
        """, (col_id,))
        return [r[0] for r in cur.fetchall()]

    # Check NLP papers
    nlp_col_id = result.get("nlp_subcollection_id")
    nlp_titles_in_col = get_titles_in_collection(nlp_col_id)
    for title in NLP_TITLES:
        if title in nlp_titles_in_col:
            result["nlp_papers_present"].append(title)
        else:
            result["nlp_papers_missing"].append(title)
    result["nlp_paper_count"] = len(result["nlp_papers_present"])

    # Check Vision papers
    vis_col_id = result.get("vision_subcollection_id")
    vis_titles_in_col = get_titles_in_collection(vis_col_id)
    for title in VISION_TITLES:
        if title in vis_titles_in_col:
            result["vision_papers_present"].append(title)
        else:
            result["vision_papers_missing"].append(title)
    result["vision_paper_count"] = len(result["vision_papers_present"])

    conn.close()
except Exception as e:
    result["error"] = str(e)
    import traceback
    result["traceback"] = traceback.format_exc()

with open("/tmp/organize_into_subcollections_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Parent 'Deep Learning Survey': {result['parent_collection_found']}")
print(f"'NLP Papers' subcollection: {result['nlp_subcollection_found']}")
print(f"'Vision Papers' subcollection: {result['vision_subcollection_found']}")
print(f"NLP papers placed: {result['nlp_paper_count']}/3 — {result['nlp_papers_present']}")
print(f"Vision papers placed: {result['vision_paper_count']}/3 — {result['vision_papers_present']}")
PYEOF

echo "=== Export Complete: organize_into_subcollections ==="
