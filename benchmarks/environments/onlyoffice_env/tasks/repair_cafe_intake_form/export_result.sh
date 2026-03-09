#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Repair Café Intake Form Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    
    # Try to save with Ctrl+S in case user hasn't saved
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

# Wait a moment for files to be fully written
sleep 1

OUTPUT_PATH="/home/ga/Documents/TextDocuments/repair_intake_formatted.docx"
SOURCE_PATH="/home/ga/Documents/TextDocuments/repair_notes_raw.docx"

echo "Checking for output files..."

if [ -f "$OUTPUT_PATH" ]; then
    echo "✅ Formatted intake form saved: $OUTPUT_PATH"
    ls -lh "$OUTPUT_PATH"
else
    echo "⚠️ Formatted document not found at expected path: $OUTPUT_PATH"
    echo "Checking if user saved with different name..."
    ls -lh /home/ga/Documents/TextDocuments/*.docx 2>/dev/null || echo "No DOCX files found"
fi

if [ -f "$SOURCE_PATH" ]; then
    echo "✅ Source document still exists: $SOURCE_PATH"
else
    echo "⚠️ Source document missing (this is okay if renamed)"
fi

echo "=== Export Complete ==="