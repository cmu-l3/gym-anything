#!/bin/bash
echo "=== Exporting rename_attachment_metadata Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Retrieve the attachment key saved during setup
if [ -f /tmp/task_att_key.txt ]; then
    ATT_KEY=$(cat /tmp/task_att_key.txt)
else
    echo "ERROR: Attachment key not found"
    ATT_KEY=""
fi

STORAGE_DIR="/home/ga/Jurism/storage/$ATT_KEY"

# Check file system state
OLD_FILE_EXISTS="false"
NEW_FILE_EXISTS="false"
NEW_FILENAME=""
NEW_FILE_MTIME="0"

if [ -n "$ATT_KEY" ] && [ -d "$STORAGE_DIR" ]; then
    # Check for old file
    if [ -f "$STORAGE_DIR/scan_generic.pdf" ]; then
        OLD_FILE_EXISTS="true"
    fi
    
    # Check for any PDF that contains "Marbury"
    FOUND_FILE=$(find "$STORAGE_DIR" -name "*Marbury*.pdf" | head -n 1)
    if [ -n "$FOUND_FILE" ]; then
        NEW_FILE_EXISTS="true"
        NEW_FILENAME=$(basename "$FOUND_FILE")
        NEW_FILE_MTIME=$(stat -c %Y "$FOUND_FILE")
    fi
fi

# Check Database State
DB_PATH=$(get_jurism_db)
DB_PATH_VAL=""
DB_TITLE_VAL=""

if [ -n "$DB_PATH" ] && [ -n "$ATT_KEY" ]; then
    # Get the path stored in itemAttachments
    DB_PATH_VAL=$(sqlite3 "$DB_PATH" "SELECT path FROM itemAttachments JOIN items ON itemAttachments.itemID=items.itemID WHERE items.key='$ATT_KEY'" 2>/dev/null || echo "")
    
    # Get the title (filename display) from itemData
    # fieldID 1 is title
    DB_TITLE_VAL=$(sqlite3 "$DB_PATH" "SELECT value FROM itemDataValues JOIN itemData ON itemDataValues.valueID=itemData.valueID JOIN items ON itemData.itemID=items.itemID WHERE items.key='$ATT_KEY' AND itemData.fieldID=1" 2>/dev/null || echo "")
fi

# Create JSON result
# Use python to safely escape strings for JSON
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'att_key': '$ATT_KEY',
    'old_file_exists': $OLD_FILE_EXISTS,
    'new_file_exists': $NEW_FILE_EXISTS,
    'new_filename': '''$NEW_FILENAME''',
    'new_file_mtime': $NEW_FILE_MTIME,
    'db_path_value': '''$DB_PATH_VAL''',
    'db_title_value': '''$DB_TITLE_VAL''',
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=4)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="