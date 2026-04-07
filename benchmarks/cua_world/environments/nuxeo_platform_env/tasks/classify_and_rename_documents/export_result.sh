#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities to access Nuxeo API
source /workspace/scripts/task_utils.sh

# Record task timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
echo "Capturing final state..."
ga_x "scrot /tmp/task_final.png" 2>/dev/null || true
SCREENSHOT_EXISTS="false"
[ -f /tmp/task_final.png ] && SCREENSHOT_EXISTS="true"

# 2. Retrieve Document IDs
DOC1_UID=$(cat /tmp/doc1_uid.txt 2>/dev/null || echo "")
DOC2_UID=$(cat /tmp/doc2_uid.txt 2>/dev/null || echo "")

echo "Retrieving state for Doc1: $DOC1_UID"
echo "Retrieving state for Doc2: $DOC2_UID"

# 3. Query Nuxeo API for current state of documents
# We query by UID because the title/name might have changed
DOC1_JSON="{}"
DOC2_JSON="{}"

if [ -n "$DOC1_UID" ]; then
    DOC1_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/id/$DOC1_UID")
fi

if [ -n "$DOC2_UID" ]; then
    DOC2_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/id/$DOC2_UID")
fi

# 4. Extract specific fields using Python for safety
# We construct a clean JSON result file for the verifier
python3 -c "
import sys, json, os

try:
    doc1 = json.loads('''$DOC1_JSON''')
except:
    doc1 = {}

try:
    doc2 = json.loads('''$DOC2_JSON''')
except:
    doc2 = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'screenshot_exists': '$SCREENSHOT_EXISTS' == 'true',
    'doc1': {
        'uid': doc1.get('uid'),
        'title': doc1.get('properties', {}).get('dc:title', ''),
        'nature': doc1.get('properties', {}).get('dc:nature', ''),
        'last_modified': doc1.get('lastModified', '')
    },
    'doc2': {
        'uid': doc2.get('uid'),
        'title': doc2.get('properties', {}).get('dc:title', ''),
        'nature': doc2.get('properties', {}).get('dc:nature', ''),
        'last_modified': doc2.get('lastModified', '')
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so the host can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json