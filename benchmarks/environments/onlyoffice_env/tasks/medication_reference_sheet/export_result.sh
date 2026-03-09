#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Medication Reference Document Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window and saving document..."
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 3

    # Close ONLYOFFICE
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
fi

# Wait a moment for file to be fully written
sleep 2

DOC_PATH="/home/ga/Documents/TextDocuments/medication_reference.docx"

if [ -f "$DOC_PATH" ]; then
    FILE_SIZE=$(stat -c%s "$DOC_PATH" 2>/dev/null || stat -f%z "$DOC_PATH" 2>/dev/null || echo "unknown")
    echo "✅ Document saved: $DOC_PATH"
    echo "   File size: $FILE_SIZE bytes"
    ls -lh "$DOC_PATH" 2>/dev/null || true
else
    echo "⚠️ Warning: Document not found at expected location: $DOC_PATH"
    echo "Checking if document was saved elsewhere..."
    find /home/ga/Documents -name "*.docx" -type f -mmin -5 2>/dev/null || true
fi

echo "=== Export Complete ==="