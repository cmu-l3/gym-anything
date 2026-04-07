#!/bin/bash
echo "=== Exporting Bulk Tag task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Function to get document info (tags and modification time)
get_doc_info() {
    local path="$1"
    # Fetch document with properties. 'nxtag:tags' stores tags.
    # We also check 'dc:modified' to see if it was touched.
    curl -s -u "$NUXEO_AUTH" \
        -H "Content-Type: application/json" \
        -H "X-NXproperties: *" \
        "$NUXEO_URL/api/v1/path$path"
}

# Fetch info for all relevant documents
echo "Querying document states..."
DOC1=$(get_doc_info "/default-domain/workspaces/Projects/Legacy-Policy-2020")
DOC2=$(get_doc_info "/default-domain/workspaces/Templates/Legacy-Policy-Template")
DOC3=$(get_doc_info "/default-domain/workspaces/DeepStorage/Legacy-Policy-Draft")
DOC4=$(get_doc_info "/default-domain/workspaces/Projects/Active-Policy-2024")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "documents": {
        "legacy_project": $DOC1,
        "legacy_template": $DOC2,
        "legacy_storage": $DOC3,
        "active_policy": $DOC4
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="