#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Handmade Soap Care Sheet Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window and saving..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Save the document
    save_document ga :1
    sleep 2
    
    # Try saving again to be sure
    save_document ga :1
    sleep 1

    # Close ONLYOFFICE
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

# Wait for file to be fully written
sleep 2

DOC_PATH="/home/ga/Documents/TextDocuments/Soap_Care_Instructions.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Document saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
    
    # Check file size to ensure it's not empty
    FILE_SIZE=$(stat -f%z "$DOC_PATH" 2>/dev/null || stat -c%s "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ Document has substantial content (${FILE_SIZE} bytes)"
    else
        echo "⚠️ Document seems small (${FILE_SIZE} bytes) - may not be complete"
    fi
else
    echo "⚠️ Document not found: $DOC_PATH"
    echo "Checking if it was saved elsewhere..."
    find /home/ga/Documents -name "*Soap*" -o -name "*soap*" 2>/dev/null || true
fi

echo "=== Export Complete ==="