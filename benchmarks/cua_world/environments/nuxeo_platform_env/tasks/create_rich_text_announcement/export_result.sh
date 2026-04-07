#!/bin/bash
# export_result.sh for create_rich_text_announcement
set -e

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (Evidence of UI state)
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Collect Task Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query the Nuxeo API for the created document
# We try the expected path. If the user named it slightly differently, 
# the verifier might fail or we could search, but for strict verification we check the specific path.
TARGET_PATH="/default-domain/workspaces/Projects/Weekend-Maintenance-Alert"

echo "Querying document at $TARGET_PATH..."
DOC_JSON=$(curl -s -u "$NUXEO_AUTH" -H "Content-Type: application/json" \
    "$NUXEO_URL/api/v1/path$TARGET_PATH")

# Check if document was found
DOC_FOUND="false"
if echo "$DOC_JSON" | grep -q "\"entity-type\":\"document\""; then
    DOC_FOUND="true"
fi

# 4. Prepare Result JSON
# We save the raw JSON from Nuxeo to a file so Python can parse the rich text content safely
# preventing bash quoting issues with HTML.
echo "$DOC_JSON" > /tmp/nuxeo_doc.json

# Create the wrapper result structure
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "doc_found": $DOC_FOUND,
    "doc_json_path": "/tmp/nuxeo_doc.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="