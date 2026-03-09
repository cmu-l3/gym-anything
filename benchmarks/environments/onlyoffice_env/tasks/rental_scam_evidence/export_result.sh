#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Rental Scam Evidence Result ==="

USER="ga"
DISPLAY_VAR=":1"
DOC_PATH="/home/$USER/Documents/TextDocuments/rental_scam_evidence.docx"

# Check if ONLYOFFICE is running
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save and close..."
    
    # Focus window and save
    focus_onlyoffice_window || true
    sleep 1
    
    # Save document with Ctrl+S
    save_document "$USER" "$DISPLAY_VAR"
    sleep 2
    
    # Additional save attempt using Ctrl+Shift+S (Save As)
    # This might prompt for filename/location if document hasn't been saved yet
    su - $USER -c "DISPLAY=$DISPLAY_VAR xdotool key ctrl+shift+s" || true
    sleep 1
    
    # If Save As dialog appeared, we need to:
    # 1. Type the filename
    # 2. Press Enter to save
    # Let's type the full path
    su - $USER -c "DISPLAY=$DISPLAY_VAR xdotool type --delay 50 '$DOC_PATH'" || true
    sleep 1
    su - $USER -c "DISPLAY=$DISPLAY_VAR xdotool key Return" || true
    sleep 2
    
    # Close ONLYOFFICE
    close_onlyoffice "$USER" "$DISPLAY_VAR"
    sleep 2
fi

# Ensure ONLYOFFICE is fully closed
if is_onlyoffice_running; then
    echo "Force killing ONLYOFFICE..."
    kill_onlyoffice "$USER"
    sleep 1
fi

# Wait for file to be fully written
sleep 2

# Check if document was saved
if [ -f "$DOC_PATH" ]; then
    echo "✅ Document saved successfully: $DOC_PATH"
    ls -lh "$DOC_PATH"
    
    # Verify it's a valid file (non-zero size)
    FILE_SIZE=$(stat -f%z "$DOC_PATH" 2>/dev/null || stat -c%s "$DOC_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 0 ]; then
        echo "✅ Document size: $FILE_SIZE bytes (valid)"
    else
        echo "⚠️ Document is empty (0 bytes)"
    fi
else
    echo "⚠️ Document not found at expected location: $DOC_PATH"
    
    # Check alternative locations
    echo "Searching for any .docx files in Documents..."
    find /home/$USER/Documents -name "*.docx" -type f 2>/dev/null || true
    
    echo "Checking Desktop for .docx files..."
    find /home/$USER/Desktop -name "*.docx" -type f 2>/dev/null || true
fi

echo "=== Export Complete ==="