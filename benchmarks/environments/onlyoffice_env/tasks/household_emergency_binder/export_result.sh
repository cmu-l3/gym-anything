#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Household Emergency Binder Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Save the document
    save_document ga :1
    sleep 3
    
    echo "Document saved, attempting to close ONLYOFFICE..."
    # Close ONLYOFFICE gracefully
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is fully closed
if is_onlyoffice_running; then
    echo "ONLYOFFICE still running, force closing..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written to disk
sleep 2

DOC_PATH="/home/ga/Documents/TextDocuments/emergency_reference.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Emergency reference document saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
    
    # Verify file is not empty
    FILE_SIZE=$(stat -c%s "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ Document has substantial content (${FILE_SIZE} bytes)"
    elif [ "$FILE_SIZE" -gt 0 ]; then
        echo "⚠️  Document exists but may be incomplete (${FILE_SIZE} bytes)"
    else
        echo "❌ Document is empty"
    fi
else
    echo "❌ Emergency reference document not found at: $DOC_PATH"
fi

echo "=== Export Complete ==="