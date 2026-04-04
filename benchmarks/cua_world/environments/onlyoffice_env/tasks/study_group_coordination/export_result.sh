#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Study Group Coordination Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "OnlyOffice is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Save the document
    save_document ga :1
    sleep 2
    
    # Try to save again to ensure it's persisted
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    echo "Closing OnlyOffice..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "OnlyOffice still running, force killing..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 1

DOC_PATH="/home/ga/Documents/TextDocuments/study_group_plan.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Document saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
    
    # Check file size to ensure it has content
    FILE_SIZE=$(stat -f%z "$DOC_PATH" 2>/dev/null || stat -c%s "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ Document has substantial content (${FILE_SIZE} bytes)"
    else
        echo "⚠️ Document may be too small (${FILE_SIZE} bytes)"
    fi
else
    echo "⚠️ Document not found: $DOC_PATH"
fi

# Cleanup temporary log files
rm -f /tmp/onlyoffice_study_task.log 2>/dev/null || true

echo "=== Export Complete ==="