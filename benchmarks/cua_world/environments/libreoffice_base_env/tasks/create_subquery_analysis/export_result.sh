#!/bin/bash
echo "=== Exporting Subquery Analysis Result ==="

# Source utils for screenshot
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Paths
ODB_PATH="/home/ga/chinook.odb"
RESULT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check ODB file status
if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    ODB_MTIME=$(stat -c %Y "$ODB_PATH")
    
    # Check if modified since start
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        MODIFIED_DURING_TASK="true"
    else
        MODIFIED_DURING_TASK="false"
    fi
else
    ODB_EXISTS="false"
    ODB_SIZE="0"
    MODIFIED_DURING_TASK="false"
fi

# Create a temporary directory to extract the ODB content
# We need content.xml to verify the saved queries
EXTRACT_DIR=$(mktemp -d)
CONTENT_XML_PATH=""

if [ "$ODB_EXISTS" = "true" ]; then
    echo "Extracting ODB file to check content..."
    unzip -q "$ODB_PATH" "content.xml" -d "$EXTRACT_DIR" 2>/dev/null || true
    
    if [ -f "$EXTRACT_DIR/content.xml" ]; then
        CONTENT_XML_PATH="$EXTRACT_DIR/content.xml"
        echo "Found content.xml"
    else
        echo "WARNING: Could not find content.xml in ODB file"
    fi
fi

# Prepare result JSON
# We embed the content.xml content directly into JSON so verifier.py can parse it
# Escaping XML for JSON is tricky in bash, so we'll use python to generate the JSON

python3 -c "
import json
import os
import sys

def read_file(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return f.read()
    except:
        return ''

content_xml = read_file('$CONTENT_XML_PATH')
task_start = int('$TASK_START')
odb_exists = '$ODB_EXISTS' == 'true'
modified = '$MODIFIED_DURING_TASK' == 'true'

result = {
    'odb_exists': odb_exists,
    'modified_during_task': modified,
    'task_start': task_start,
    'content_xml': content_xml,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f)
"

# Clean up
rm -rf "$EXTRACT_DIR"

# Set permissions for copy_from_env
chmod 666 "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"