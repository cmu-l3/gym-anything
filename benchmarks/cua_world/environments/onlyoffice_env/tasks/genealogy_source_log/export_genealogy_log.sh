#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Genealogy Source Log ==="

# Target file path
DOC_PATH="/home/ga/Documents/TextDocuments/genealogy_source_log.docx"

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Save the document
    echo "Saving document..."
    save_document ga :1
    sleep 2
    
    # Try to save to specific path if document hasn't been saved yet
    # Send Ctrl+Shift+S for Save As dialog
    su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+shift+s" || true
    sleep 2
    
    # Type the filename
    su - ga -c "DISPLAY=:1 xdotool type --delay 50 '$DOC_PATH'" || true
    sleep 1
    
    # Press Enter to confirm
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
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

# Check if document was saved
if [ -f "$DOC_PATH" ]; then
    echo "✅ Genealogy source log saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
else
    echo "⚠️ Document not found at expected path: $DOC_PATH"
    echo "Searching for any DOCX files in TextDocuments..."
    find /home/ga/Documents/TextDocuments -name "*.docx" -type f -ls 2>/dev/null || true
fi

echo "=== Export Complete ==="