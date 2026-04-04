#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Book Club Coordinator Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

# Wait a moment for file to be fully written
sleep 1

DOC_PATH="/home/ga/Documents/BookClub_2025.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Book club handbook saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
    
    # Also check if the info file still exists
    INFO_FILE="/home/ga/Documents/bookclub_info.txt"
    if [ -f "$INFO_FILE" ]; then
        echo "✅ Reference file still present: $INFO_FILE"
    fi
else
    echo "⚠️ Book club handbook not found: $DOC_PATH"
fi

echo "=== Export Complete ==="