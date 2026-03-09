#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Freelance Tier Proposal Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    
    # Give extra time for any final edits
    sleep 1
    
    # Save the document
    save_document ga :1
    sleep 2
    
    # Try to save again to ensure it's saved
    save_document ga :1
    sleep 1

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

DOC_PATH="/home/ga/Documents/TextDocuments/client_proposal.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Proposal document saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
    
    # Check file size to ensure it's not empty
    FILE_SIZE=$(stat -f%z "$DOC_PATH" 2>/dev/null || stat -c%s "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ Document appears to have content (size: ${FILE_SIZE} bytes)"
    else
        echo "⚠️ Document may be empty or incomplete (size: ${FILE_SIZE} bytes)"
    fi
else
    echo "⚠️ Proposal document not found: $DOC_PATH"
    echo "Checking alternate locations..."
    find /home/ga/Documents -name "*proposal*.docx" -o -name "*client*.docx" 2>/dev/null || true
fi

echo "=== Export Complete ==="