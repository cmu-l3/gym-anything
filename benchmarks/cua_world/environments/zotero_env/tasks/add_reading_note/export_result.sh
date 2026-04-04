#!/bin/bash
# Export result for add_reading_note task
# Checks if a meaningful note was added to the "Attention Is All You Need" paper

echo "=== Exporting add_reading_note result ==="

DB="/home/ga/Zotero/zotero.sqlite"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Get baseline
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count 2>/dev/null || echo "0")
TARGET_PAPER_ID=$(cat /tmp/target_paper_id 2>/dev/null || echo "0")

# Give Zotero a moment to flush writes
sleep 2

# Current note count
CURRENT_NOTE_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM itemNotes" 2>/dev/null || echo "0")
NOTES_ADDED=$((CURRENT_NOTE_COUNT - INITIAL_NOTE_COUNT))

# Check for notes attached to the target paper
NOTE_FOUND="false"
NOTE_CONTENT=""
NOTE_LENGTH=0

if [ "$TARGET_PAPER_ID" != "0" ]; then
    # Get notes where parentItemID = target paper ID
    NOTE_ROW=$(sqlite3 "$DB" "SELECT note, title FROM itemNotes WHERE parentItemID=$TARGET_PAPER_ID ORDER BY rowid DESC LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$NOTE_ROW" ]; then
        NOTE_FOUND="true"
        NOTE_CONTENT=$(echo "$NOTE_ROW" | head -c 5000)
        NOTE_LENGTH=${#NOTE_CONTENT}
    fi
fi

# Use Python to check keywords robustly (handles HTML encoding in notes)
python3 << 'PYEOF'
import sqlite3
import json
import os
import html
import re

DB = "/home/ga/Zotero/zotero.sqlite"
target_id_file = "/tmp/target_paper_id"

try:
    target_id = int(open(target_id_file).read().strip())
except:
    target_id = 0

result = {
    "target_paper_id": target_id,
    "note_found": False,
    "note_content_raw": "",
    "note_content_text": "",
    "note_length": 0,
    "has_transformer": False,
    "has_self_attention": False,
    "has_translation": False,
    "notes_attached": 0,
}

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    if target_id > 0:
        cur.execute("SELECT note FROM itemNotes WHERE parentItemID=? ORDER BY rowid DESC LIMIT 1",
                    (target_id,))
        row = cur.fetchone()
        if row and row[0]:
            raw_html = row[0]
            # Strip HTML tags to get plain text
            text = re.sub(r'<[^>]+>', ' ', raw_html)
            text = html.unescape(text)
            text = ' '.join(text.split())  # normalize whitespace

            result["note_found"] = True
            result["note_content_raw"] = raw_html[:2000]
            result["note_content_text"] = text[:2000]
            result["note_length"] = len(text)

            text_lower = text.lower()
            result["has_transformer"] = "transformer" in text_lower
            result["has_self_attention"] = ("self-attention" in text_lower or
                                             "self attention" in text_lower or
                                             "selfattention" in text_lower)
            result["has_translation"] = ("translat" in text_lower)

        # Count all notes for this paper
        cur.execute("SELECT COUNT(*) FROM itemNotes WHERE parentItemID=?", (target_id,))
        result["notes_attached"] = cur.fetchone()[0]

    conn.close()
except Exception as e:
    result["error"] = str(e)

with open("/tmp/add_reading_note_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Note found: {result['note_found']}")
print(f"Note length: {result['note_length']}")
print(f"Has 'Transformer': {result['has_transformer']}")
print(f"Has 'self-attention': {result['has_self_attention']}")
print(f"Has 'translation': {result['has_translation']}")
PYEOF

echo "=== Export Complete: add_reading_note ==="
