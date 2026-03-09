#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Court Exhibit List Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window..."
    focus_onlyoffice_window || true
    sleep 1
    
    echo "Saving document..."
    save_document ga :1
    sleep 3
    
    # Close ONLYOFFICE
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
sleep 2

# Check if document exists at expected location
DOC_PATH="/home/ga/Documents/TextDocuments/Exhibit_List_SC-2025-04157.docx"

if [ -f "$DOC_PATH" ]; then
    echo "✅ Exhibit list saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
    
    # Verify it's a valid DOCX file (basic check)
    file_type=$(file "$DOC_PATH" | grep -i "microsoft word" || true)
    if [ -n "$file_type" ]; then
        echo "✅ File appears to be valid DOCX format"
    else
        echo "⚠️  File may not be in DOCX format"
    fi
else
    echo "⚠️  Expected document not found: $DOC_PATH"
    
    # Check for alternative locations/names
    echo "Checking for documents in TextDocuments directory:"
    ls -lh /home/ga/Documents/TextDocuments/*.docx 2>/dev/null || echo "No DOCX files found"
    
    # Check Desktop as fallback
    if [ -d "/home/ga/Desktop" ]; then
        echo "Checking Desktop:"
        ls -lh /home/ga/Desktop/*.docx 2>/dev/null || echo "No DOCX files on Desktop"
    fi
fi

echo "=== Export Complete ==="