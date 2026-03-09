#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Retirement Dinner Seating Chart Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Save the document
    save_document ga :1
    sleep 2
    
    # Save again to be sure (sometimes first save doesn't complete)
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE gracefully
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

# Wait a moment for file to be fully written to disk
sleep 2

DOC_PATH="/home/ga/Documents/TextDocuments/retirement_seating_chart.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Seating chart document saved: $DOC_PATH"
    FILE_SIZE=$(stat -f%z "$DOC_PATH" 2>/dev/null || stat -c%s "$DOC_PATH" 2>/dev/null || echo "unknown")
    echo "   File size: $FILE_SIZE bytes"
    ls -lh "$DOC_PATH"
else
    echo "⚠️ WARNING: Seating chart document not found at $DOC_PATH"
    echo "Checking directory contents:"
    ls -la "/home/ga/Documents/TextDocuments/" || echo "Directory does not exist"
fi

echo "=== Export Complete ==="