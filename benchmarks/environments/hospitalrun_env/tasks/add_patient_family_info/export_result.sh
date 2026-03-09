#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ─── Query CouchDB for Relevant Documents ──────────────────────────────────
# We search for ANY document containing "Carlos" and "Santos" created/modified
# This is robust against schema variations (whether it's a separate doc or embedded)

echo "[export] Searching database for Carlos Santos..."

# Fetch all docs with include_docs=true
# Filter in Python for flexibility
QUERY_RESULT=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
    rows = data.get('rows', [])
    
    matches = []
    
    for row in rows:
        doc = row.get('doc', {})
        doc_str = json.dumps(doc).lower()
        
        # Check for key terms
        if 'carlos' in doc_str and 'santos' in doc_str:
            matches.append(doc)
            
    # Output matches
    print(json.dumps({
        'matches': matches,
        'count': len(matches),
        'total_docs_in_db': len(rows)
    }))

except Exception as e:
    print(json.dumps({'error': str(e), 'matches': []}))
")

# Get initial count for comparison
INITIAL_COUNT=$(cat /tmp/initial_doc_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(echo "$QUERY_RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_docs_in_db', 0))" 2>/dev/null || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_db_count": $INITIAL_COUNT,
    "current_db_count": $CURRENT_COUNT,
    "query_result": $QUERY_RESULT,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "Found matches:"
echo "$QUERY_RESULT" | jq '.count' 2>/dev/null || echo "0"
echo "=== Export complete ==="