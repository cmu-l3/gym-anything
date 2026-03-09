#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Student Loan Comparison Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    save_document ga :1
    sleep 3

    # Try to close gracefully
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is fully closed
if is_onlyoffice_running; then
    echo "ONLYOFFICE still running, forcing close..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/loan_comparison.xlsx"

if [ -f "$SHEET_PATH" ]; then
    FILE_SIZE=$(stat -c%s "$SHEET_PATH" 2>/dev/null || stat -f%z "$SHEET_PATH" 2>/dev/null || echo "unknown")
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    echo "   File size: $FILE_SIZE bytes"
    ls -lh "$SHEET_PATH" || true
else
    echo "⚠️  Warning: Expected spreadsheet not found at: $SHEET_PATH"
    echo "   Checking for alternative locations..."
    find /home/ga/Documents -name "*loan*.xlsx" -o -name "*comparison*.xlsx" 2>/dev/null || true
fi

echo "=== Export Complete ==="