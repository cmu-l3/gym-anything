#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting RPG Session Prep Result ==="

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

DOC_PATH="/home/ga/Documents/TextDocuments/session_notes.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Document saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
else
    echo "⚠️ Document not found: $DOC_PATH"
fi

echo "=== Export Complete ==="