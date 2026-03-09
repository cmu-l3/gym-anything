#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Tenant Complaint Letter Result ==="

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

DOC_PATH="/home/ga/Documents/TextDocuments/complaint_letter.docx"

if [ -f "$DOC_PATH" ]; then
    FILE_SIZE=$(stat -f%z "$DOC_PATH" 2>/dev/null || stat -c%s "$DOC_PATH" 2>/dev/null)
    echo "✅ Complaint letter saved: $DOC_PATH"
    echo "   File size: ${FILE_SIZE} bytes"
    ls -lh "$DOC_PATH"
    
    if [ "$FILE_SIZE" -lt 2000 ]; then
        echo "⚠️  WARNING: Document seems small (${FILE_SIZE} bytes)"
        echo "   Expected size for complete letter: 5000+ bytes"
    fi
else
    echo "❌ ERROR: Document not found at $DOC_PATH"
    exit 1
fi

echo "=== Export Complete ==="