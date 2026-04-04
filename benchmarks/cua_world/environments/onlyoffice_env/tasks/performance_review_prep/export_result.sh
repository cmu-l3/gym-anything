#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Performance Review Prep Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    
    # Save with current name first (in case user already renamed)
    save_document ga :1
    sleep 2
    
    # Try to do Save As with the expected filename
    # This is optional - user might have already renamed the file
    echo "Attempting to ensure correct filename..."
    
    # Final save
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

EXPECTED_PATH="/home/ga/Documents/TextDocuments/Maya_Thompson_2024_Brag_Sheet.docx"
DRAFT_PATH="/home/ga/Documents/TextDocuments/achievement_notes_2024_DRAFT.docx"

# Check if the expected filename exists
if [ -f "$EXPECTED_PATH" ]; then
    echo "✅ Document saved with correct filename: $EXPECTED_PATH"
    ls -lh "$EXPECTED_PATH"
elif [ -f "$DRAFT_PATH" ]; then
    echo "⚠️  Document saved but still has original filename: $DRAFT_PATH"
    echo "    (Verification will check both locations)"
    ls -lh "$DRAFT_PATH"
else
    echo "⚠️ Document not found at expected locations"
    echo "    Checking for any modified .docx files..."
    find /home/ga/Documents/TextDocuments/ -name "*.docx" -type f -mmin -5 || true
fi

echo "=== Export Complete ==="