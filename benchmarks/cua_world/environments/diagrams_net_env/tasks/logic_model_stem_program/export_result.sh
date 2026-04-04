#!/bin/bash
echo "=== Exporting logic_model_stem_program results ==="

# Define paths
DRAWIO_FILE="/home/ga/Diagrams/stem_logic_model.drawio"
PDF_FILE="/home/ga/Diagrams/stem_logic_model.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Files
DRAWIO_EXISTS=false
DRAWIO_MODIFIED=false
DRAWIO_CONTENT=""
PDF_EXISTS=false

if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$DRAWIO_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        DRAWIO_MODIFIED=true
    fi
    # Extract text content from XML (simple grep for verification)
    # We strip XML tags to just get the raw text content for keyword matching
    DRAWIO_CONTENT=$(grep -o 'value="[^"]*"' "$DRAWIO_FILE" | sed 's/value="//;s/"//' | tr '\n' ' ')
fi

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS=true
fi

# 3. Create Result JSON
# We include the raw content so the verifier can check for keywords
# We use Python to safely construct the JSON to avoid escaping issues
python3 -c "
import json
import os

try:
    content = '''$DRAWIO_CONTENT'''
except:
    content = ''

result = {
    'timestamp': $CURRENT_TIME,
    'task_start': $TASK_START,
    'drawio_exists': '$DRAWIO_EXISTS' == 'true',
    'drawio_modified': '$DRAWIO_MODIFIED' == 'true',
    'pdf_exists': '$PDF_EXISTS' == 'true',
    'drawio_content_preview': content[:5000] if content else ''
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# 4. Permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"