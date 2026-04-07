#!/bin/bash
# Export script for unpublish_document task
# Verifies the state of the section and the workspace using Nuxeo API

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Get IDs from setup
ORIGINAL_DOC_ID=$(cat /tmp/original_doc_id.txt 2>/dev/null || echo "")
SECTION_ID=$(cat /tmp/section_id.txt 2>/dev/null || echo "")

# 2. Check if Original Document still exists in Workspace
# We check by ID to ensure it's the specific object we created
ORIGINAL_CHECK_JSON=$(nuxeo_api GET "/id/$ORIGINAL_DOC_ID")
ORIGINAL_EXISTS=$(echo "$ORIGINAL_CHECK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid') == '$ORIGINAL_DOC_ID')" 2>/dev/null || echo "False")
ORIGINAL_IS_TRASHED=$(echo "$ORIGINAL_CHECK_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('isTrashed', False))" 2>/dev/null || echo "True")

# 3. Check if Proxy exists in Section
# We query children of the section. It should be empty or at least NOT contain our doc title.
# (Publishing creates a proxy, which has a different UUID, so we search by title/path inside section)
SECTION_CHILDREN_JSON=$(nuxeo_api GET "/id/$SECTION_ID/@children")
PROXY_COUNT=$(echo "$SECTION_CHILDREN_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
entries = data.get('entries', [])
# Count documents with the specific title we created
count = sum(1 for d in entries if d.get('title') == 'HR Policy 2024 Draft' and not d.get('isTrashed'))
print(count)
" 2>/dev/null || echo "0")

# 4. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 5. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 6. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "original_exists": $([ "$ORIGINAL_EXISTS" = "True" ] && echo "true" || echo "false"),
    "original_is_trashed": $([ "$ORIGINAL_IS_TRASHED" = "True" ] && echo "true" || echo "false"),
    "section_proxy_count": $PROXY_COUNT,
    "task_start_ts": $TASK_START,
    "task_end_ts": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json