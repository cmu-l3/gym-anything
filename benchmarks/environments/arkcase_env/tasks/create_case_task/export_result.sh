#!/bin/bash
echo "=== Exporting create_case_task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CASE_NUMBER=$(cat /tmp/parent_case_number.txt 2>/dev/null || echo "")
INITIAL_TASK_COUNT=$(cat /tmp/initial_task_count.txt 2>/dev/null || echo "0")

echo "Exporting for Case: $CASE_NUMBER"

# Ensure port-forward is active for API calls
ensure_portforward

# ── 1. Search for the specific task created ──────────────────────────────────
# Search by title keywords and parent case
# We search specifically for the title requested in the prompt
TARGET_TITLE="Review Response Package for Completeness"
# URL encode the title for Solr
ENCODED_TITLE=$(echo "$TARGET_TITLE" | sed 's/ /+/g')

echo "Searching for task: $TARGET_TITLE"
TASK_SEARCH_RESPONSE=$(curl -sk \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Accept: application/json" \
    "${ARKCASE_URL}/api/v1/plugin/search/advancedSearch?query=object_type_s:TASK+AND+title_parseable:\"$ENCODED_TITLE\"&start=0&rows=10" 2>/dev/null || echo "{}")

# ── 2. Get current task count for the case ───────────────────────────────────
CURRENT_TASK_COUNT=0
if [ -n "$CASE_NUMBER" ]; then
    CURRENT_TASK_COUNT=$(curl -sk \
        -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
        -H "Accept: application/json" \
        "${ARKCASE_URL}/api/v1/plugin/search/advancedSearch?query=object_type_s:TASK+AND+parent_number_lcs:${CASE_NUMBER}&start=0&rows=0" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response',{}).get('numFound', 0))" 2>/dev/null || echo "0")
fi

echo "Task count change: $INITIAL_TASK_COUNT -> $CURRENT_TASK_COUNT"

# ── 3. Take final screenshot ─────────────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── 4. Create JSON Result ────────────────────────────────────────────────────
# Use Python to construct valid JSON from the search response and other vars
python3 -c "
import json
import os
import sys

try:
    search_response = json.loads('''$TASK_SEARCH_RESPONSE''')
    docs = search_response.get('response', {}).get('docs', [])
    
    # Filter for best match if multiple
    target_title = \"$TARGET_TITLE\"
    found_task = None
    
    for doc in docs:
        title = doc.get('title_parseable', doc.get('name', ''))
        # Check if title matches reasonably well
        if 'Review Response Package' in title:
            found_task = doc
            break
            
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'case_number': \"$CASE_NUMBER\",
        'initial_task_count': int(\"$INITIAL_TASK_COUNT\"),
        'current_task_count': int(\"$CURRENT_TASK_COUNT\"),
        'task_found': found_task is not None,
        'task_data': found_task if found_task else {},
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    print(f'Error creating JSON: {e}')
    # Fallback JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'task_found': False}, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="