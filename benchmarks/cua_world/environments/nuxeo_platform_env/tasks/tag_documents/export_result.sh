#!/bin/bash
# export_result.sh for tag_documents
# Queries Nuxeo API for tags on the modified documents and exports verification data.

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to get document details (tags + modification time)
get_doc_details() {
    local path="$1"
    # We use the 'tags' enricher to get the tags in the response
    # Context-Parameters header tells Nuxeo to include the 'tags' enricher
    curl -s -u "$NUXEO_AUTH" \
        -H "enrichers-document: tags" \
        -H "X-NXDocumentProperties: *" \
        -H "Content-Type: application/json" \
        "$NUXEO_URL/api/v1/path$path"
}

# 1. Fetch data for Annual Report
echo "Fetching Annual Report data..."
JSON_REP1=$(get_doc_details "/default-domain/workspaces/Projects/Annual-Report-2023")

# 2. Fetch data for Project Proposal
echo "Fetching Project Proposal data..."
JSON_REP2=$(get_doc_details "/default-domain/workspaces/Projects/Project-Proposal")

# 3. Fetch data for Q3 Status Report
echo "Fetching Q3 Status Report data..."
JSON_REP3=$(get_doc_details "/default-domain/workspaces/Projects/Q3-Status-Report")

# 4. Capture Final Screenshot
echo "Capturing final screenshot..."
ga_x "scrot /tmp/task_final.png" 2>/dev/null || true

# 5. Construct Result JSON using Python for reliability
# We pass the raw JSON strings from curl to python to parse and restructure safely.
python3 -c "
import sys, json, time

try:
    start_time = int('$TASK_START')
    
    # Load raw responses
    d1 = json.loads('''$JSON_REP1''') if '$JSON_REP1' else {}
    d2 = json.loads('''$JSON_REP2''') if '$JSON_REP2' else {}
    d3 = json.loads('''$JSON_REP3''') if '$JSON_REP3' else {}

    def extract_info(doc):
        if not doc or 'uid' not in doc:
            return {'exists': False, 'tags': [], 'modified_at': 0}
        
        # Extract tags from contextParameters or fallback
        tags = []
        cp = doc.get('contextParameters', {})
        if 'tags' in cp:
            # tags is usually a list of objects or strings depending on version
            # In Nuxeo Platform LTS 2021/2023, it's often a list of tag objects {label: 'xyz'} or just strings
            raw_tags = cp['tags']
            for t in raw_tags:
                if isinstance(t, dict):
                    tags.append(t.get('label', ''))
                else:
                    tags.append(str(t))
        
        # Extract modification time
        # Format example: 2023-10-25T12:00:00.00Z
        last_mod = doc.get('lastModified', '')
        mod_ts = 0
        if last_mod:
            # Simple parsing or just string comparison if format is standard ISO
            # For verification, we just need to know if it changed. 
            # We'll pass the string to python verifier to handle date parsing if needed, 
            # or try basic conversion here.
            pass
            
        return {
            'exists': True,
            'tags': tags,
            'last_modified': last_mod,
            'uid': doc.get('uid')
        }

    result = {
        'task_start': start_time,
        'task_end': int(time.time()),
        'documents': {
            'Annual-Report-2023': extract_info(d1),
            'Project-Proposal': extract_info(d2),
            'Q3-Status-Report': extract_info(d3)
        },
        'screenshot_path': '/tmp/task_final.png'
    }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    # Fallback in case of python error
    print(f'Error creating JSON: {e}', file=sys.stderr)
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)

"

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="