#!/bin/bash
echo "=== Exporting annotate_pdf_highlight result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

DB_PATH="/home/ga/Zotero/zotero.sqlite"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Allow Zotero to flush DB changes
sleep 2

# Helper python script to query complex Zotero 7 annotation schema
cat > /tmp/query_annotations.py << 'EOF'
import sqlite3
import json
import sys

db_path = "/home/ga/Zotero/zotero.sqlite"
target_title = "Attention Is All You Need"

result = {
    "paper_found": False,
    "attachment_found": False,
    "attachment_path": None,
    "annotation_found": False,
    "highlight_text": None,
    "comment_text": None,
    "annotation_count": 0
}

try:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # 1. Find the parent paper itemID
    cur.execute("""
        SELECT i.itemID FROM items i
        JOIN itemData d ON i.itemID = d.itemID
        JOIN itemDataValues v ON d.valueID = v.valueID
        WHERE d.fieldID = 1 AND v.value LIKE ?
    """, (f"%{target_title}%",))
    
    paper = cur.fetchone()
    if paper:
        result["paper_found"] = True
        paper_id = paper[0]
        
        # 2. Find PDF attachment (child item)
        # itemTypeID 14 is classic attachment, but Zotero 7 might use different ID
        # We look for any child that is an attachment (has path)
        cur.execute("""
            SELECT itemID, path FROM itemAttachments
            WHERE parentItemID = ? AND (contentType = 'application/pdf' OR path LIKE '%.pdf')
        """, (paper_id,))
        
        attachment = cur.fetchone()
        if attachment:
            result["attachment_found"] = True
            attachment_id = attachment[0]
            result["attachment_path"] = attachment[1]
            
            # 3. Find Annotations (children of the attachment)
            # In Zotero 7, annotations are items linked to the attachment
            # Metadata is in itemAnnotations table
            
            cur.execute("""
                SELECT text, comment FROM itemAnnotations
                WHERE parentItemID = ?
            """, (attachment_id,))
            
            annotations = cur.fetchall()
            result["annotation_count"] = len(annotations)
            
            for ann in annotations:
                text = ann[0]
                comment = ann[1]
                
                # Check for our specific content logic here or just export all
                # We export the first valid one we find for verification
                if text:
                    result["highlight_text"] = text
                    result["annotation_found"] = True
                if comment:
                    result["comment_text"] = comment

    conn.close()

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
EOF

# Execute query
QUERY_RESULT=$(python3 /tmp/query_annotations.py)

# Check if application is running
APP_RUNNING=$(pgrep -f "zotero" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "db_query_result": $QUERY_RESULT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="