#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Home Walkthrough Inspector Result ==="

SHEET_PATH="/home/ga/Documents/Spreadsheets/home_inspection_walkthrough.xlsx"

# Focus ONLYOFFICE and attempt to save with proper filename
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Try to trigger Save As dialog with Ctrl+Shift+S, then provide filename
    echo "Attempting to save with specific filename..."
    su - ga -c "DISPLAY=:1 xdotool key ctrl+shift+s" || true
    sleep 2
    
    # Clear any existing filename and type the desired path
    su - ga -c "DISPLAY=:1 xdotool key ctrl+a" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool type '$SHEET_PATH'" || true
    sleep 1
    
    # Press Enter to confirm save
    su - ga -c "DISPLAY=:1 xdotool key Return" || true
    sleep 2
    
    # Also try regular save (Ctrl+S) as fallback
    echo "Performing regular save..."
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is fully closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait for file system to sync
sleep 2

# Check if file was saved at expected location
if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved successfully: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Show file details for debugging
    file "$SHEET_PATH" || true
else
    echo "⚠️ Spreadsheet not found at expected location: $SHEET_PATH"
    
    # Search for any xlsx files that might have been saved elsewhere
    echo "Searching for xlsx files in Documents..."
    find /home/ga/Documents -name "*.xlsx" -type f -mmin -5 2>/dev/null | head -10 || true
    
    # Check default save location
    if [ -d "/home/ga/Documents" ]; then
        ls -la /home/ga/Documents/*.xlsx 2>/dev/null || echo "No xlsx files in /home/ga/Documents"
    fi
fi

echo "=== Export Complete ==="