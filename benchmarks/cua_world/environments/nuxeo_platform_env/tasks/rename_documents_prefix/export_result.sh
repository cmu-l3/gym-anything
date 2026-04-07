#!/bin/bash
# Export script for rename_documents_prefix task
# Queries the API for the current titles of the target documents
# and captures the final screenshot.

echo "=== Exporting rename_documents_prefix results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to get doc title via API
get_doc_title() {
    local path="$1"
    nuxeo_api GET "/path$path" | python3 -c "import sys,json; print(json.load(sys.stdin).get('properties',{}).get('dc:title','MISSING'))" 2>/dev/null || echo "ERROR"
}

# Helper to get doc UID (to verify it wasn't deleted/recreated if we tracked IDs, 
# but for this task path existence is sufficient for basic verification)
get_doc_uid() {
    local path="$1"
    nuxeo_api GET "/path$path" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uid','MISSING'))" 2>/dev/null || echo "ERROR"
}

# Collect current state of the 3 documents
TITLE_1=$(get_doc_title "/default-domain/workspaces/Projects/Annual-Report-2023")
TITLE_2=$(get_doc_title "/default-domain/workspaces/Projects/Project-Proposal")
TITLE_3=$(get_doc_title "/default-domain/workspaces/Projects/Q3-Status-Report")

UID_1=$(get_doc_uid "/default-domain/workspaces/Projects/Annual-Report-2023")
UID_2=$(get_doc_uid "/default-domain/workspaces/Projects/Project-Proposal")
UID_3=$(get_doc_uid "/default-domain/workspaces/Projects/Q3-Status-Report")

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "documents": {
        "/default-domain/workspaces/Projects/Annual-Report-2023": {
            "title": "$TITLE_1",
            "uid": "$UID_1"
        },
        "/default-domain/workspaces/Projects/Project-Proposal": {
            "title": "$TITLE_2",
            "uid": "$UID_2"
        },
        "/default-domain/workspaces/Projects/Q3-Status-Report": {
            "title": "$TITLE_3",
            "uid": "$UID_3"
        }
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json