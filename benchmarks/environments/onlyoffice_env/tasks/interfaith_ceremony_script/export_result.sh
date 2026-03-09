#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Interfaith Ceremony Script Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2

    # Try to save again to ensure it's saved
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
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

# Check for both possible file names
DOC_PATH_NEW="/home/ga/Documents/TextDocuments/ceremony_script.docx"
DOC_PATH_ORIG="/home/ga/Documents/TextDocuments/ceremony_draft.docx"

if [ -f "$DOC_PATH_NEW" ]; then
    echo "✅ Ceremony script saved as: $DOC_PATH_NEW"
    ls -lh "$DOC_PATH_NEW"
elif [ -f "$DOC_PATH_ORIG" ]; then
    echo "✅ Ceremony script saved as: $DOC_PATH_ORIG (original name)"
    ls -lh "$DOC_PATH_ORIG"
else
    echo "⚠️  Warning: Ceremony document not found at expected paths"
    echo "Checking Documents directory..."
    ls -lh /home/ga/Documents/TextDocuments/*.docx 2>/dev/null || echo "No .docx files found"
fi

echo "=== Export Complete ==="