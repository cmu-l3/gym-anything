#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Community Grant Proposal Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window..."
    focus_onlyoffice_window || true
    sleep 1
    
    echo "Saving document..."
    save_document ga :1
    sleep 2

    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
fi

# Wait a moment for file to be fully written
sleep 1

DOC_PATH="/home/ga/Documents/CommunityGrant_Proposal.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Proposal document saved: $DOC_PATH"
    FILE_SIZE=$(stat -c%s "$DOC_PATH" 2>/dev/null || stat -f%z "$DOC_PATH" 2>/dev/null)
    echo "   File size: $FILE_SIZE bytes"
    ls -lh "$DOC_PATH"
    
    # Basic file validation
    if [ "$FILE_SIZE" -lt 5000 ]; then
        echo "⚠️  WARNING: File seems small, may not contain expected content"
    else
        echo "✅ File size looks reasonable"
    fi
else
    echo "❌ ERROR: Proposal document not found at $DOC_PATH"
    echo "   Checking directory contents:"
    ls -lh /home/ga/Documents/ || true
fi

echo "=== Export Complete ==="