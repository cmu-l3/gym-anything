#!/bin/bash
# Export script for update_document_thumbnail task

echo "=== Exporting update_document_thumbnail results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
ga_x "scrot /tmp/task_final.png" 2>/dev/null || true

# 2. Retrieve Initial State
INITIAL_STATE_FILE="/tmp/task_initial_state.json"
if [ -f "$INITIAL_STATE_FILE" ]; then
    INITIAL_PDF_DIGEST=$(jq -r .initial_pdf_digest "$INITIAL_STATE_FILE")
    TARGET_THUMBNAIL_DIGEST=$(jq -r .target_thumbnail_digest "$INITIAL_STATE_FILE")
    DOC_PATH=$(jq -r .doc_path "$INITIAL_STATE_FILE")
else
    echo "ERROR: Initial state file not found."
    INITIAL_PDF_DIGEST=""
    TARGET_THUMBNAIL_DIGEST=""
    DOC_PATH="/default-domain/workspaces/Projects/Q3-Marketing-Report"
fi

# 3. Query Current Document State
echo "Querying document state from Nuxeo API..."
DOC_JSON=$(curl -s -u "$NUXEO_AUTH" -H "X-NXproperties: thumb,file,dublincore" "$NUXEO_URL/api/v1/path$DOC_PATH")

# Extract properties using Python for reliability
read -r FINAL_PDF_DIGEST FINAL_THUMB_DIGEST DOC_TITLE <<EOF
$(echo "$DOC_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    props = data.get('properties', {})
    
    # file:content might be null if deleted
    file_content = props.get('file:content')
    pdf_digest = file_content.get('digest', '') if file_content else 'null'
    
    # thumb:thumbnail might be null
    thumb = props.get('thumb:thumbnail')
    thumb_digest = thumb.get('digest', '') if thumb else 'null'
    
    title = props.get('dc:title', '')
    
    print(f'{pdf_digest} {thumb_digest} {title}')
except Exception:
    print('error error error')
")
EOF

# 4. Check for App State
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 5. Build Result JSON
# We calculate verification flags here to simplify the python verifier, 
# or pass raw data to python verifier. Passing raw data is better.

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat <<EOF > "$TEMP_JSON"
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "initial_pdf_digest": "$INITIAL_PDF_DIGEST",
    "target_thumbnail_digest": "$TARGET_THUMBNAIL_DIGEST",
    "final_pdf_digest": "$FINAL_PDF_DIGEST",
    "final_thumbnail_digest": "$FINAL_THUMB_DIGEST",
    "doc_title": "$DOC_TITLE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json