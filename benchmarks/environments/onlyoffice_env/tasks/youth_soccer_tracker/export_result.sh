#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Youth Soccer Tracker Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    
    # Extra save attempt to ensure final file is saved
    save_document ga :1
    sleep 3
    
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

FINAL_PATH="/home/ga/Documents/Spreadsheets/soccer_progress_final.xlsx"
TEMPLATE_PATH="/home/ga/Documents/Spreadsheets/soccer_progress_template.xlsx"

if [ -f "$FINAL_PATH" ]; then
    echo "✅ Final spreadsheet saved: $FINAL_PATH"
    ls -lh "$FINAL_PATH"
else
    echo "⚠️ Final spreadsheet not found: $FINAL_PATH"
    echo "Checking if template was modified instead..."
    if [ -f "$TEMPLATE_PATH" ]; then
        echo "Template exists at: $TEMPLATE_PATH"
        ls -lh "$TEMPLATE_PATH"
    fi
fi

# List all xlsx files in the directory for debugging
echo ""
echo "All spreadsheet files in directory:"
ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || echo "No xlsx files found"

echo "=== Export Complete ==="