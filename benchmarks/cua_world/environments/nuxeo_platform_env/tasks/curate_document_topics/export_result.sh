#!/bin/bash
# Post-task export for curate_document_topics
# Queries Nuxeo API for the final state of the documents

set -e
echo "=== Exporting curate_document_topics results ==="

NUXEO_URL="http://localhost:8080/nuxeo"
NUXEO_AUTH="Administrator:Administrator"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to get document JSON
get_doc_json() {
    local path="$1"
    curl -s -u "$NUXEO_AUTH" \
        -H "Content-Type: application/json" \
        -H "X-NXproperties: dublincore" \
        "$NUXEO_URL/api/v1/path$path" || echo "{}"
}

echo "Querying document states..."

# Get Project Specifications state
DOC1_JSON=$(get_doc_json "/default-domain/workspaces/Projects/Project-Specifications")

# Get Gallery Brochure state
DOC2_JSON=$(get_doc_json "/default-domain/workspaces/Projects/Gallery-Brochure")

# Construct Result JSON
# We embed the raw doc JSONs so python can parse them safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "doc1_raw": $DOC1_JSON,
    "doc2_raw": $DOC2_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="