#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Escape Room Hint System Result ==="

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

FINAL_DOC_PATH="/home/ga/Documents/alchemist_hints_final.docx"

if [ -f "$FINAL_DOC_PATH" ]; then
    echo "✅ Document saved: $FINAL_DOC_PATH"
    ls -lh "$FINAL_DOC_PATH"
else
    echo "⚠️ Document not found: $FINAL_DOC_PATH"
    echo "Checking for alternative locations..."
    find /home/ga -name "*alchemist*" -o -name "*hint*" 2>/dev/null || true
fi

echo "=== Export Complete ==="