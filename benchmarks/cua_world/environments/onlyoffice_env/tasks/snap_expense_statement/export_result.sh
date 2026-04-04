#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting SNAP Expense Statement Result ==="

# Focus ONLYOFFICE and save all documents
if is_onlyoffice_running; then
    # Try to focus and save the spreadsheet
    focus_onlyoffice_window || true
    sleep 1
    
    # Save with Ctrl+S
    save_document ga :1
    sleep 3

    # Close all ONLYOFFICE windows
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is fully closed
if is_onlyoffice_running; then
    echo "Force killing remaining ONLYOFFICE instances..."
    kill_onlyoffice ga
    sleep 2
fi

# Wait for file system to sync
sleep 1

# Check if the expected output file exists
SHEET_PATH="/home/ga/Documents/Spreadsheets/SNAP_Expense_Statement.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ SNAP Expense Statement saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️  Primary file not found: $SHEET_PATH"
    
    # Check for common alternative locations/names
    echo "Searching for alternative files..."
    find /home/ga/Documents -name "*.xlsx" -type f -mmin -10 2>/dev/null | while read file; do
        echo "  Found: $file"
    done
fi

# Also check if the notes file still exists
NOTES_PATH="/home/ga/Documents/expense_notes.txt"
if [ -f "$NOTES_PATH" ]; then
    echo "✅ Expense notes file exists: $NOTES_PATH"
else
    echo "⚠️  Notes file missing: $NOTES_PATH"
fi

echo "=== Export Complete ==="