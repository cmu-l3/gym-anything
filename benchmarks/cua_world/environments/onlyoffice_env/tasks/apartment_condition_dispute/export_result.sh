#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Apartment Dispute Document ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window and saving document..."
    focus_onlyoffice_window || true
    sleep 1
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 2

DOC_PATH="/home/ga/Documents/TextDocuments/apartment_dispute/output.docx"

if [ -f "$DOC_PATH" ]; then
    FILE_SIZE=$(stat -c%s "$DOC_PATH" 2>/dev/null || stat -f%z "$DOC_PATH" 2>/dev/null)
    echo "✅ Document saved: $DOC_PATH"
    echo "   File size: $FILE_SIZE bytes"
    ls -lh "$DOC_PATH"
    
    if [ "$FILE_SIZE" -lt 5000 ]; then
        echo "⚠️  Warning: Document may be too small (less than 5KB)"
    fi
else
    echo "❌ Document not found: $DOC_PATH"
fi

echo "=== Export Complete ==="