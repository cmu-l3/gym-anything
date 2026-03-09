#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting ADU Zoning Variance Result ==="

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

OUTPUT_FILE="/home/ga/Documents/TextDocuments/zoning_variance_application.docx"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
    echo "✅ Document saved: $OUTPUT_FILE"
    echo "📊 File size: $FILE_SIZE bytes"
    ls -lh "$OUTPUT_FILE"
    
    if [ "$FILE_SIZE" -lt 5000 ]; then
        echo "⚠️ Warning: File size seems small, document may be incomplete"
    fi
else
    echo "❌ Document not found: $OUTPUT_FILE"
fi

echo "=== Export Complete ==="