#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Foster Behavioral Log Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window and saving document..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Save document
    save_document ga :1
    sleep 3
    
    # Try to close gracefully
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is fully closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Also close gedit if still open
GEDIT_PID=$(pgrep -u ga gedit || true)
if [ -n "$GEDIT_PID" ]; then
    echo "Closing gedit..."
    sudo -u ga pkill -9 gedit || true
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 2

# Check if the output document exists
OUTPUT_DOC="$WORKSPACE_DIR/jamie_placement_review.docx"
OUTPUT_DOC="/home/ga/Documents/TextDocuments/jamie_placement_review.docx"

if [ -f "$OUTPUT_DOC" ]; then
    echo "✅ Placement review document saved: $OUTPUT_DOC"
    ls -lh "$OUTPUT_DOC"
    
    # Verify it's a valid file with content
    FILE_SIZE=$(stat -f%z "$OUTPUT_DOC" 2>/dev/null || stat -c%s "$OUTPUT_DOC" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 10000 ]; then
        echo "✅ Document has substantial content (${FILE_SIZE} bytes)"
    else
        echo "⚠️  Document seems small (${FILE_SIZE} bytes) - may be incomplete"
    fi
else
    echo "⚠️  Placement review document not found: $OUTPUT_DOC"
    echo "Checking for any .docx files in workspace..."
    find /home/ga/Documents/TextDocuments/ -name "*.docx" -ls || true
fi

# Verify raw notes file still exists
RAW_NOTES="/home/ga/Documents/TextDocuments/jamie_raw_notes.txt"
if [ -f "$RAW_NOTES" ]; then
    echo "✅ Raw notes file preserved: $RAW_NOTES"
else
    echo "⚠️  Raw notes file missing (unexpected)"
fi

echo "=== Export Complete ==="