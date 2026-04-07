#!/bin/bash
echo "=== Exporting configure_vocabulary_entries results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Vocabulary Entries
echo "Querying 'nature' vocabulary..."
VOCAB_RESPONSE=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/directory/nature")

# Save raw vocab response to temp file for python processing
echo "$VOCAB_RESPONSE" > /tmp/vocab_entries.json

# 3. Query Document Metadata
echo "Querying document metadata..."
DOC_RESPONSE=$(curl -s -u "$NUXEO_AUTH" -H "X-NXproperties: dublincore" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023")

# Save raw doc response
echo "$DOC_RESPONSE" > /tmp/doc_metadata.json

# 4. Verify Application State (is Firefox running?)
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 5. Process data into final JSON result using Python
# We do the logic here to produce a clean JSON for the verifier
python3 -c "
import json
import os
import sys

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'app_was_running': $APP_RUNNING,
    'screenshot_path': '/tmp/task_final.png',
    'vocab_entries': {},
    'document_nature': None,
    'document_modified': 0
}

# Parse Vocabulary
try:
    with open('/tmp/vocab_entries.json', 'r') as f:
        data = json.load(f)
        entries = data.get('entries', [])
        # Create a dict of id -> label for easy lookup
        vocab_map = {}
        for entry in entries:
            props = entry.get('properties', {})
            eid = props.get('id', '')
            label = props.get('label', '')
            if eid:
                vocab_map[eid] = label
        result['vocab_entries'] = vocab_map
except Exception as e:
    result['vocab_error'] = str(e)

# Parse Document
try:
    with open('/tmp/doc_metadata.json', 'r') as f:
        doc = json.load(f)
        props = doc.get('properties', {})
        result['document_nature'] = props.get('dc:nature')
        
        # Check last modified time
        last_mod = doc.get('lastModified', '')
        # Nuxeo returns ISO8601, we just pass it through or compare loosely
        result['document_last_modified'] = last_mod
except Exception as e:
    result['doc_error'] = str(e)

print(json.dumps(result, indent=2))
" > /tmp/processed_result.json

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/processed_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="