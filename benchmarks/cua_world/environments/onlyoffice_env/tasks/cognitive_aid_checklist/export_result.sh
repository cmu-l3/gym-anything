#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Cognitive Aid Checklist Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
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
sleep 1

DOC_PATH="/home/ga/Documents/TextDocuments/gas_leak_procedure.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Document saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
    
    # Quick file size check
    FILE_SIZE=$(stat -f%z "$DOC_PATH" 2>/dev/null || stat -c%s "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ Document appears to have content (${FILE_SIZE} bytes)"
    else
        echo "⚠️  Document may be empty or minimal (${FILE_SIZE} bytes)"
    fi
else
    echo "⚠️  Document not found: $DOC_PATH"
fi

echo "=== Export Complete ==="