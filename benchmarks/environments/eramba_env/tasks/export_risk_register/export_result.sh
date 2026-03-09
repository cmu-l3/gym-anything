#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOWNLOAD_DIR="/home/ga/Downloads"

# Initialize result variables
FILE_FOUND="false"
FILE_PATH=""
FILE_SIZE="0"
IS_FRESH="false"
CONTENT_MATCH="false"
FOUND_KEYWORDS=""

# Find the most recently modified file in Downloads
# We look for .csv, .xlsx, or .xls
TARGET_FILE=$(find "$DOWNLOAD_DIR" -type f \( -name "*.csv" -o -name "*.xlsx" -o -name "*.xls" \) -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)

if [ -n "$TARGET_FILE" ] && [ -f "$TARGET_FILE" ]; then
    FILE_FOUND="true"
    FILE_PATH="$TARGET_FILE"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE")
    
    # Check freshness (anti-gaming)
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_FRESH="true"
    fi

    # Check content for keywords ("Phishing", "Ransomware")
    # We use python for robust text extraction from potentially binary (xlsx) files
    # or simple text files (csv)
    CONTENT_CHECK=$(python3 -c "
import sys
import zipfile
import re

filepath = '$TARGET_FILE'
keywords = ['Phishing', 'Ransomware']
found = []

try:
    content = ''
    if filepath.endswith('.xlsx'):
        # Extract sharedStrings.xml from xlsx (where text is stored)
        try:
            with zipfile.ZipFile(filepath, 'r') as z:
                if 'xl/sharedStrings.xml' in z.namelist():
                    content = z.read('xl/sharedStrings.xml').decode('utf-8', errors='ignore')
                else:
                    # Fallback: read all xmls
                    for name in z.namelist():
                        if name.endswith('.xml'):
                            content += z.read(name).decode('utf-8', errors='ignore')
        except:
            # If zip fail, maybe it's just a misnamed csv? treat as text
            with open(filepath, 'r', errors='ignore') as f:
                content = f.read()
    else:
        # Assume CSV/Text
        with open(filepath, 'r', errors='ignore') as f:
            content = f.read()
            
    for k in keywords:
        if k in content:
            found.append(k)

    print(','.join(found))
except Exception as e:
    print('')
")
    
    if [ -n "$CONTENT_CHECK" ]; then
        CONTENT_MATCH="true"
        FOUND_KEYWORDS="$CONTENT_CHECK"
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_found": $FILE_FOUND,
    "file_path": "$FILE_PATH",
    "file_size_bytes": $FILE_SIZE,
    "is_fresh": $IS_FRESH,
    "content_match": $CONTENT_MATCH,
    "found_keywords": "$FOUND_KEYWORDS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="