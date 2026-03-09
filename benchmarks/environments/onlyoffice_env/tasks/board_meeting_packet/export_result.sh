#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Board Meeting Packet Result ==="

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

DOC_PATH="/home/ga/Documents/BoardMeeting/December_Board_Packet.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Board meeting packet saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
else
    echo "⚠️ Document not found at expected location: $DOC_PATH"
    echo "Checking for any .docx files in BoardMeeting directory:"
    find /home/ga/Documents/BoardMeeting -name "*.docx" -ls 2>/dev/null || true
fi

echo "=== Export Complete ==="