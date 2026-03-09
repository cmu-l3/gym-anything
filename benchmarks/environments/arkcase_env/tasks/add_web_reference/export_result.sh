#!/bin/bash
echo "=== Exporting add_web_reference result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_final.png

# Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CASE_ID=$(cat /tmp/target_case_id.txt 2>/dev/null || echo "")

echo "Exporting data for Case ID: $CASE_ID"

# 1. Fetch References for the specific case
# ArkCase API endpoints for references can vary by version/plugin, 
# typically /api/v1/service/item/{objectId}/references or similar.
# We will try to fetch the case details which might include references, 
# or query the reference service directly.

REF_DATA="[]"

if [ -n "$CASE_ID" ]; then
    # Try Method A: Specific references endpoint
    echo "Querying references endpoint..."
    RESP_A=$(arkcase_api GET "service/item/${CASE_ID}/references")
    
    # Check if response is valid JSON array or object
    if echo "$RESP_A" | grep -q "\"url\""; then
        REF_DATA="$RESP_A"
    else
        # Try Method B: Search endpoint generic query for children
        # This is a fallback if the direct reference endpoint isn't standard
        echo "Querying generic search..."
        # (Simplified for this task: usually we assume Method A works for standard ArkCase)
        REF_DATA="$RESP_A" 
    fi
fi

# Save raw API response to debug file
echo "$REF_DATA" > /tmp/api_references_debug.json

# Process data into a clean result JSON
# We use Python to parse the API response and extract relevant fields
python3 -c "
import sys, json, time

try:
    # Load API response
    raw_data = '''$REF_DATA'''
    try:
        data = json.loads(raw_data)
    except:
        data = []

    # Handle if data is wrapped in a 'references' key or is a list
    if isinstance(data, dict):
        refs = data.get('references', data.get('searchResults', []))
        if not isinstance(refs, list):
             # sometimes it returns a single object if only one exists? unlikely but possible
             refs = [data] if data.get('url') else []
    else:
        refs = data

    found_refs = []
    
    # Expected values for loose matching
    target_url = 'justice.gov/foia'
    
    for r in refs:
        # Extract fields safely
        url = r.get('url', '')
        title = r.get('title', r.get('name', ''))
        desc = r.get('description', '')
        
        # Timestamps in ArkCase are usually milliseconds
        created = r.get('createdDate', r.get('created', 0))
        if created > 1000000000000: # Convert ms to sec
            created = created / 1000
            
        found_refs.append({
            'url': url,
            'title': title,
            'description': desc,
            'created_ts': created
        })

    result = {
        'task_start_ts': $TASK_START,
        'case_id': '$CASE_ID',
        'references': found_refs,
        'api_response_valid': True if refs else False
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    # Fallback error JSON
    print(json.dumps({
        'error': str(e),
        'task_start_ts': $TASK_START,
        'references': []
    }))

" > /tmp/task_result.json

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="