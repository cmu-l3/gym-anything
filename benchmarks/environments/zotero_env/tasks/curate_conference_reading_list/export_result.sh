#!/bin/bash
echo "=== Exporting curate_conference_reading_list results ==="

# Define paths
DB_PATH="/home/ga/Zotero/zotero.sqlite"
RESULT_FILE="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Ensure DB is accessible (force flush not strictly needed for SQLite WAL, but good practice)
sync

# Use Python to handle complex logic (JSON generation, HTML parsing, fuzzy matching)
python3 -c "
import sqlite3
import json
import os
import re
import html

db_path = '$DB_PATH'
task_start_file = '/tmp/task_start_time.txt'

result = {
    'collection_exists': False,
    'collection_id': None,
    'items_in_collection': [],
    'correct_items_found': [],
    'incorrect_items_found': [],
    'tags_correct': {},  # Map itemID -> bool
    'standalone_note_exists': False,
    'note_content_valid': False,
    'note_length': 0,
    'referenced_papers': [],
    'task_timestamp_valid': False
}

try:
    # Check timestamp
    if os.path.exists(task_start_file):
        with open(task_start_file, 'r') as f:
            start_time = int(f.read().strip())
        # Ideally check if collection created after start_time, but SQLite doesn't store creation time by default easily
        # We assume clean state from setup_task.sh
        result['task_timestamp_valid'] = True

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 1. Check if Collection exists
    cursor.execute(\"SELECT collectionID FROM collections WHERE collectionName = 'NeurIPS Preparation'\")
    row = cursor.fetchone()
    
    if row:
        result['collection_exists'] = True
        coll_id = row[0]
        result['collection_id'] = coll_id

        # 2. Get items in collection (excluding notes/attachments: type 1 and 14)
        # itemTypeID: 1=note, 14=attachment. We want bibliographic items.
        query = \"\"\"
            SELECT i.itemID, v.value 
            FROM collectionItems ci
            JOIN items i ON ci.itemID = i.itemID
            JOIN itemData d ON i.itemID = d.itemID
            JOIN itemDataValues v ON d.valueID = v.valueID
            WHERE ci.collectionID = ? 
            AND d.fieldID = 1 
            AND i.itemTypeID NOT IN (1, 14)
        \"\"\"
        cursor.execute(query, (coll_id,))
        items = cursor.fetchall()

        target_papers = [
            \"Attention Is All You Need\",
            \"Language Models are Few-Shot Learners\",
            \"ImageNet Classification with Deep Convolutional Neural Networks\",
            \"Generative Adversarial Nets\"
        ]

        for item_id, title in items:
            item_info = {'id': item_id, 'title': title, 'tags': []}
            
            # Check if this title is in our target list (substring match usually sufficient/safer)
            is_target = any(t.lower() in title.lower() for t in target_papers)
            
            if is_target:
                result['correct_items_found'].append(title)
            else:
                result['incorrect_items_found'].append(title)

            # 3. Check tags for this item
            tag_query = \"\"\"
                SELECT t.name 
                FROM itemTags it
                JOIN tags t ON it.tagID = t.tagID
                WHERE it.itemID = ?
            \"\"\"
            cursor.execute(tag_query, (item_id,))
            tags = [r[0] for r in cursor.fetchall()]
            
            has_correct_tag = 'neurips-reading' in tags
            result['tags_correct'][item_id] = has_correct_tag
            item_info['tags'] = tags
            result['items_in_collection'].append(item_info)

        # 4. Check for Standalone Note in Collection
        # Standalone notes have parentItemID IS NULL and are linked in collectionItems
        note_query = \"\"\"
            SELECT n.note 
            FROM itemNotes n
            JOIN collectionItems ci ON n.itemID = ci.itemID
            WHERE ci.collectionID = ? AND n.parentItemID IS NULL
        \"\"\"
        cursor.execute(note_query, (coll_id,))
        note_row = cursor.fetchone()
        
        if note_row:
            result['standalone_note_exists'] = True
            raw_note = note_row[0]
            # Strip HTML
            clean_text = re.sub('<[^<]+?>', '', raw_note)
            clean_text = html.unescape(clean_text)
            result['note_length'] = len(clean_text)
            
            # Check length
            if len(clean_text) >= 150:
                result['note_content_valid'] = True
                
            # Check references
            # We look for significant fragments of the titles
            check_fragments = [
                \"Attention Is All You Need\", \"Transformer\",
                \"Language Models\", \"Few-Shot\",
                \"ImageNet\", \"Convolutional\",
                \"Generative Adversarial\", \"GAN\"
            ]
            
            found_refs = 0
            # Group fragments by paper to count distinct paper references
            paper_checks = {
                \"Vaswani\": [\"Attention Is All You Need\", \"Transformer\"],
                \"Brown\": [\"Language Models\", \"Few-Shot\"],
                \"Krizhevsky\": [\"ImageNet\", \"Convolutional\"],
                \"Goodfellow\": [\"Generative Adversarial\", \"GAN\"]
            }
            
            referenced = []
            for paper, fragments in paper_checks.items():
                if any(frag.lower() in clean_text.lower() for frag in fragments):
                    referenced.append(paper)
            
            result['referenced_papers'] = referenced

    conn.close()

except Exception as e:
    result['error'] = str(e)

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="