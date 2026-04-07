#!/bin/bash
# Export script for archive_note_as_pdf task
# Verifies the existence and properties of the archived PDF document via API.

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Nuxeo API for the archived document
# We look for a File document with the specific title in the Projects workspace
echo "Querying Nuxeo for archived document..."

QUERY="SELECT * FROM Document WHERE ecm:parentId = (SELECT ecm:uuid FROM Document WHERE ecm:path = '/default-domain/workspaces/Projects') AND dc:title = 'Q3 Status Report - Archived' AND ecm:isTrashed = 0"

# URL encode the query
ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote(\"$QUERY\"))")

SEARCH_RESULT=$(nuxeo_api GET "/search/lang/NXQL/execute?query=$ENCODED_QUERY")

# 3. Check for local file download (evidence of export)
# We check if any PDF was downloaded to ~/Downloads during the task window
DOWNLOAD_EVIDENCE="false"
DOWNLOADED_FILE=""
if [ -d "/home/ga/Downloads" ]; then
    # Find files modified/created after task start
    RECENT_PDF=$(find /home/ga/Downloads -name "*.pdf" -newermt "@$TASK_START" 2>/dev/null | head -n 1)
    if [ -n "$RECENT_PDF" ]; then
        DOWNLOAD_EVIDENCE="true"
        DOWNLOADED_FILE="$RECENT_PDF"
    fi
fi

# 4. Check if original Note still exists
NOTE_CHECK=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/Q3-Status-Report")
NOTE_EXISTS="false"
if echo "$NOTE_CHECK" | grep -q "\"type\":\"Note\""; then
    NOTE_EXISTS="true"
fi

# 5. Construct JSON result
# We save the raw search result (metadata) for the verifier to parse safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "search_result": $SEARCH_RESULT,
    "download_evidence": $DOWNLOAD_EVIDENCE,
    "downloaded_file": "$DOWNLOADED_FILE",
    "original_note_exists": $NOTE_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="