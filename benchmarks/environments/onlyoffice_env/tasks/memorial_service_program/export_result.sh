#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Memorial Service Program Result ==="

WORKSPACE_DIR="/home/ga/Documents/MemorialService"
EXPECTED_FILE="$WORKSPACE_DIR/final_service_program.docx"

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Try to save the document
    save_document ga :1
    sleep 3
    
    # Try to close gracefully
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 1

# Check if the expected file exists
if [ -f "$EXPECTED_FILE" ]; then
    echo "✅ Memorial service program saved: $EXPECTED_FILE"
    ls -lh "$EXPECTED_FILE"
    
    # Show file size for verification
    FILE_SIZE=$(stat -f%z "$EXPECTED_FILE" 2>/dev/null || stat -c%s "$EXPECTED_FILE" 2>/dev/null)
    echo "   File size: $FILE_SIZE bytes"
    
    if [ "$FILE_SIZE" -lt 1000 ]; then
        echo "⚠️  Warning: File size seems small, document may be incomplete"
    fi
else
    echo "⚠️  Expected file not found: $EXPECTED_FILE"
    echo "Files in workspace:"
    ls -lh "$WORKSPACE_DIR/" 2>/dev/null || echo "Directory not found"
    
    # Check if file might have been saved elsewhere
    echo ""
    echo "Checking for any .docx files in Documents:"
    find /home/ga/Documents -name "*.docx" -type f -mmin -10 2>/dev/null || echo "No recent .docx files found"
fi

echo "=== Export Complete ==="