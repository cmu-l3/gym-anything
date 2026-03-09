#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Retrieve IDs
ORIGINAL_CASE_ID=$(cat /tmp/original_case_id.txt 2>/dev/null || echo "")
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query the Original Case (to check rename and description update)
echo "Fetching original case details..."
ORIGINAL_CASE_JSON="{}"
if [ -n "$ORIGINAL_CASE_ID" ]; then
    ORIGINAL_CASE_JSON=$(arkcase_api GET "plugin/complaint/$ORIGINAL_CASE_ID" 2>/dev/null || echo "{}")
fi

# 4. Search for the New Case (Sanitation)
echo "Searching for new sanitation case..."
# We search by title keyword "Sanitation"
SEARCH_RESULTS=$(arkcase_api GET "plugin/complaint?details=Sanitation" 2>/dev/null || echo "[]")
# Filter for cases created after start time (rough check via ID or timestamp if available, 
# but for now we'll trust the search and verify content in python)

# 5. Fetch Associations (Links) for Original Case
echo "Fetching associations..."
ASSOCIATIONS_JSON="[]"
if [ -n "$ORIGINAL_CASE_ID" ]; then
    # Endpoint structure varies, assuming standard plugin sub-resource
    ASSOCIATIONS_JSON=$(arkcase_api GET "plugin/complaint/$ORIGINAL_CASE_ID/references" 2>/dev/null || echo "[]")
fi

# 6. Fetch Notes for Original Case
echo "Fetching notes..."
NOTES_JSON="[]"
if [ -n "$ORIGINAL_CASE_ID" ]; then
    NOTES_JSON=$(arkcase_api GET "plugin/complaint/$ORIGINAL_CASE_ID/notes" 2>/dev/null || echo "[]")
fi

# 7. Compile Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $START_TIME,
    "original_case_id": "$ORIGINAL_CASE_ID",
    "original_case_data": $ORIGINAL_CASE_JSON,
    "search_results": $SEARCH_RESULTS,
    "associations": $ASSOCIATIONS_JSON,
    "notes": $NOTES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"