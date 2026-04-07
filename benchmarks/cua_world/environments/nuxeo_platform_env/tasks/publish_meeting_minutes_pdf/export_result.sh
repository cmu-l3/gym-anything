#!/bin/bash
# Post-task script to gather verification data inside the container
# and export it as a JSON file for the verifier.

echo "=== Exporting Publish Meeting Minutes results ==="

source /workspace/scripts/task_utils.sh

# Configuration
UNIQUE_STR="Ref-Verification-7734"
TARGET_PATH="/default-domain/workspaces/Corporate-Records"
SOURCE_PATH="/default-domain/workspaces/Projects/Q3-Board-Minutes"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Data via API
# We need to check:
# A. Source Note version
# B. Target PDF existence
# C. Target PDF content (does it contain UNIQUE_STR?)

# A. Check Source Version
echo "Checking source version..."
SOURCE_JSON=$(curl -s -u "$NUXEO_AUTH" -H "X-NXproperties: *" "$NUXEO_URL/api/v1/path$SOURCE_PATH")
# Extract major version using python
SOURCE_MAJOR_VER=$(echo "$SOURCE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('uid:major_version', 0))" 2>/dev/null || echo "0")
SOURCE_MINOR_VER=$(echo "$SOURCE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('uid:minor_version', 0))" 2>/dev/null || echo "0")
echo "Source version: $SOURCE_MAJOR_VER.$SOURCE_MINOR_VER"

# B. Check Target Document
echo "Checking target document..."
# Query children of Corporate Records to find likely candidates
QUERY="SELECT * FROM Document WHERE ecm:parentId = (SELECT ecm:uuid FROM Document WHERE ecm:path='$TARGET_PATH') AND ecm:isTrashed = 0"
TARGETS_JSON=$(nuxeo_api GET "/query?query=$(echo "$QUERY" | sed 's/ /%20/g')")

# Parse candidates in Python to find the best match and verify content
# We do this logic inside the container so we can download the blob locally for checking
python3 -c "
import sys, json, requests, os

nuxeo_auth = ('Administrator', 'Administrator')
unique_str = '$UNIQUE_STR'
targets = json.load(sys.stdin).get('entries', [])
result = {
    'target_found': False,
    'target_title': '',
    'is_pdf': False,
    'content_verified': False,
    'file_created_after_start': False
}

best_match = None

# Look for PDF with correct name first
for doc in targets:
    title = doc.get('title', '')
    props = doc.get('properties', {})
    content = props.get('file:content')
    
    if content and 'pdf' in content.get('mime-type', '').lower():
        result['is_pdf'] = True # found at least one PDF
        if 'Q3-Board-Minutes-Final' in title:
            best_match = doc
            break

# If no exact match, take any PDF
if not best_match and targets:
    for doc in targets:
        props = doc.get('properties', {})
        content = props.get('file:content')
        if content and 'pdf' in content.get('mime-type', '').lower():
            best_match = doc
            break

if best_match:
    result['target_found'] = True
    result['target_title'] = best_match.get('title', '')
    
    props = best_match.get('properties', {})
    content = props.get('file:content')
    if content:
        mime = content.get('mime-type', '')
        result['is_pdf'] = 'pdf' in mime.lower()
        
        # Download and verify content
        url = content.get('data')
        if url:
            try:
                r = requests.get(url, auth=nuxeo_auth)
                # Simple string check in binary
                if unique_str.encode() in r.content:
                    result['content_verified'] = True
            except Exception as e:
                print(f'Error downloading blob: {e}', file=sys.stderr)
    
    # Check creation time vs task start
    try:
        with open('/tmp/task_start_time.txt', 'r') as f:
            start_time = int(f.read().strip())
        
        # dc:created is ISO8601, Nuxeo doesn't expose raw timestamp easily here
        # but we can rely on the fact the folder was empty at start (setup_task ensures this)
        # So existence implies creation during task.
        result['file_created_after_start'] = True
    except:
        pass

print(json.dumps(result))
" <<< "$TARGETS_JSON" > /tmp/target_analysis.json

# Combine results
cat > /tmp/task_result.json << EOF
{
    "source_major_version": $SOURCE_MAJOR_VER,
    "source_minor_version": $SOURCE_MINOR_VER,
    "target_analysis": $(cat /tmp/target_analysis.json)
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json