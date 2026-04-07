#!/bin/bash
# Export results for add_document_attachment task

source /workspace/scripts/task_utils.sh

echo "=== Exporting add_document_attachment results ==="

# ---------------------------------------------------------------------------
# Capture Final State
# ---------------------------------------------------------------------------
# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get Document State from API
PP_PATH="/default-domain/workspaces/Projects/Project-Proposal"
DOC_JSON=$(nuxeo_api GET "/path$PP_PATH")

# Get Initial State
INITIAL_STATE_FILE="/tmp/initial_state.json"
if [ -f "$INITIAL_STATE_FILE" ]; then
    INITIAL_COUNT=$(python3 -c "import json; print(json.load(open('$INITIAL_STATE_FILE')).get('attachment_count', 0))" 2>/dev/null)
    INITIAL_MODIFIED=$(python3 -c "import json; print(json.load(open('$INITIAL_STATE_FILE')).get('modified_timestamp', ''))" 2>/dev/null)
    TASK_START=$(python3 -c "import json; print(json.load(open('$INITIAL_STATE_FILE')).get('task_start_time', 0))" 2>/dev/null)
else
    INITIAL_COUNT=0
    INITIAL_MODIFIED=""
    TASK_START=0
fi

# ---------------------------------------------------------------------------
# Analyze Document State
# ---------------------------------------------------------------------------
# We extract values here to JSON to avoid complex parsing in python verifier without libraries
# Python script to parse the Nuxeo JSON response and output a flat verification JSON

python3 -c "
import sys, json, os
from datetime import datetime

try:
    doc = json.loads(os.environ.get('DOC_JSON', '{}'))
    initial_mod = os.environ.get('INITIAL_MODIFIED', '')
    task_start = float(os.environ.get('TASK_START', 0))
    initial_count = int(os.environ.get('INITIAL_COUNT', 0))

    props = doc.get('properties', {})
    
    # 1. Document Existence
    exists = doc.get('uid') is not None
    
    # 2. Main File Preservation
    main_file = props.get('file:content')
    main_file_preserved = False
    main_file_name = ''
    if main_file and isinstance(main_file, dict):
        main_file_preserved = True
        main_file_name = main_file.get('name', '')
    
    # 3. Attachments
    attachments = props.get('files:files', [])
    current_count = len(attachments)
    count_increased = current_count > initial_count
    
    # 4. Attachment Content Check
    found_target = False
    target_size = 0
    target_name = ''
    
    for att in attachments:
        blob = att.get('file', {})
        if blob and isinstance(blob, dict):
            fname = blob.get('name', '')
            if 'Q3' in fname and 'Status' in fname:
                found_target = True
                target_size = blob.get('length', 0)
                target_name = fname
                break
    
    # 5. Modification Time
    current_mod = props.get('dc:modified', '')
    modified_after_start = False
    if current_mod:
        try:
            # Handle Nuxeo ISO format (e.g. 2023-10-27T10:00:00.00Z)
            # Simple string comparison works for ISO if TZ is same, but let's try strict
            dt_str = current_mod.replace('Z', '+00:00')
            dt = datetime.fromisoformat(dt_str)
            if dt.timestamp() > task_start:
                modified_after_start = True
        except:
            pass
            
    # Timestamp changed check (fallback)
    timestamp_changed = current_mod != initial_mod

    result = {
        'doc_exists': exists,
        'main_file_preserved': main_file_preserved,
        'main_file_name': main_file_name,
        'attachment_count': current_count,
        'initial_count': initial_count,
        'count_increased': count_increased,
        'target_attachment_found': found_target,
        'target_attachment_name': target_name,
        'target_attachment_size': target_size,
        'modified_after_start': modified_after_start,
        'timestamp_changed': timestamp_changed,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(result, indent=2))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/task_result.json

# Export DOC_JSON variable for the python script above
export DOC_JSON="$DOC_JSON" 
export INITIAL_MODIFIED="$INITIAL_MODIFIED"
export TASK_START="$TASK_START"
export INITIAL_COUNT="$INITIAL_COUNT"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json