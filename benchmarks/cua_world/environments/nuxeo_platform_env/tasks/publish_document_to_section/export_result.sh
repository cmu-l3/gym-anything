#!/bin/bash
# Export script for publish_document_to_section task
# Checks Nuxeo API for the published document and exports results to JSON

source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_section_doc_count.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check: Document exists in Public Reports section
# We query for non-Folder/Section documents inside the target path
ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote(\"SELECT * FROM Document WHERE ecm:path STARTSWITH '/default-domain/sections/Public-Reports' AND ecm:primaryType != 'Section' AND ecm:isTrashed = 0\"))")

SEARCH_RESULT=$(curl -s -u "$NUXEO_AUTH" \
    -H "Content-Type: application/json" \
    -H "X-NXproperties: *" \
    "$NUXEO_URL/api/v1/search/lang/NXQL/execute?query=$ENCODED_QUERY" 2>/dev/null)

# Parse the search result
# Extract: count, title of first doc, isProxy status
PYTHON_PARSE_SCRIPT=$(cat <<EOF
import sys, json
try:
    data = json.load(sys.stdin)
    count = data.get('resultsCount', 0)
    entries = data.get('entries', [])
    
    doc_info = {
        "count": count,
        "title": "",
        "is_proxy": False,
        "path": ""
    }
    
    if entries:
        # Check if any entry matches the expected title
        target_entry = None
        for entry in entries:
            t = entry.get('title', '').lower()
            if 'annual' in t and 'report' in t and '2023' in t:
                target_entry = entry
                break
        
        # If no strict match, take the first one
        if not target_entry:
            target_entry = entries[0]
            
        doc_info["title"] = target_entry.get('title', '')
        doc_info["is_proxy"] = target_entry.get('isProxy', False)
        doc_info["path"] = target_entry.get('path', '')

    print(json.dumps(doc_info))
except Exception as e:
    print(json.dumps({"error": str(e), "count": 0}))
EOF
)

PARSED_RESULT=$(echo "$SEARCH_RESULT" | python3 -c "$PYTHON_PARSE_SCRIPT")

# 3. Check: Original document still exists
ORIG_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023")
ORIGINAL_EXISTS=$([ "$ORIG_CODE" = "200" ] && echo "true" || echo "false")

# 4. Construct Final JSON
# We embed the parsed python dict into the final JSON structure
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_doc_count": $INITIAL_COUNT,
    "original_exists": $ORIGINAL_EXISTS,
    "search_result": $PARSED_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (ensure readable by all)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="