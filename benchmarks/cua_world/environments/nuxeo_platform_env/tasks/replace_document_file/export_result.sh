#!/bin/bash
# post_task hook for replace_document_file task.
# Exports final document state and verification data.

echo "=== Exporting replace_document_file results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
REPLACEMENT_FILE="/home/ga/nuxeo/data/Q3_Status_Report.pdf"

# 2. Get verification data
INITIAL_DIGEST=$(cat /tmp/initial_digest.txt 2>/dev/null || echo "")

# Get current document state from API
DOC_PATH="/default-domain/workspaces/Templates/Contract-Template"
DOC_JSON=$(curl -s -u "$NUXEO_AUTH" -H "X-NXproperties: *" "$NUXEO_URL/api/v1/path$DOC_PATH")

# Get replacement file size for comparison
if [ -f "$REPLACEMENT_FILE" ]; then
    EXPECTED_SIZE=$(stat -c%s "$REPLACEMENT_FILE")
else
    EXPECTED_SIZE=0
fi

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create Result JSON
# We use Python to construct valid JSON safely
python3 -c "
import json
import os
import sys

try:
    doc = json.loads('''$DOC_JSON''')
    doc_exists = True
except:
    doc = {}
    doc_exists = False

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_digest': '$INITIAL_DIGEST',
    'doc_exists': doc_exists,
    'uid': doc.get('uid'),
    'path': doc.get('path'),
    'title': doc.get('properties', {}).get('dc:title'),
    'description': doc.get('properties', {}).get('dc:description'),
    'last_modified': doc.get('properties', {}).get('dc:modified'),
    'blob_digest': doc.get('properties', {}).get('file:content', {}).get('digest'),
    'blob_filename': doc.get('properties', {}).get('file:content', {}).get('name'),
    'blob_length': doc.get('properties', {}).get('file:content', {}).get('length'),
    'expected_file_size': $EXPECTED_SIZE,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="