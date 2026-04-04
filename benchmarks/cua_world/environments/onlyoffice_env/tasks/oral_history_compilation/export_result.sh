#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Oral History Compilation Result ==="

# Try to close text editor first (if it was opened)
pkill -f "xdg-open.*oral_history_notes.txt" 2>/dev/null || true
pkill gedit 2>/dev/null || true
pkill mousepad 2>/dev/null || true
sleep 1

OUTPUT_FILE="/home/ga/Documents/TextDocuments/oral_history_final.docx"

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    sleep 1
    
    # First try Save As with full path
    echo "Attempting to save document as $OUTPUT_FILE..."
    su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+shift+s" || true
    sleep 2
    
    # Clear any existing filename and type the full path
    su - ga -c "DISPLAY=:1 xdotool key --delay 50 ctrl+a" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool type --delay 50 '$OUTPUT_FILE'" || true
    sleep 1
    
    # Press Enter to confirm save
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 2
    
    # Also try regular save (in case file was already saved once)
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
sleep 2

if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Document saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
    file_size=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null || echo "0")
    echo "File size: $file_size bytes"
    
    if [ "$file_size" -lt 1000 ]; then
        echo "⚠️ Warning: File size is very small, document may not be properly formatted"
    fi
else
    echo "⚠️ Document not found: $OUTPUT_FILE"
    echo "Checking what files exist in directory:"
    ls -la /home/ga/Documents/TextDocuments/ || true
fi

echo "=== Export Complete ==="