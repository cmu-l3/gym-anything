#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Property Tax Appeal Results ==="

# If ONLYOFFICE is running, save and close
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    save_document ga :1
    sleep 2
    
    # Try to close gracefully
    close_onlyoffice ga :1
    sleep 2
fi

# Force kill if still running
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait for files to be fully written
sleep 2

# Check for both expected files
SPREADSHEET_PATH="/home/ga/Documents/Spreadsheets/property_comparison.xlsx"
LETTER_PATH="/home/ga/Documents/TextDocuments/tax_appeal_letter.docx"

echo ""
echo "=== Checking for completed files ==="

if [ -f "$SPREADSHEET_PATH" ]; then
    echo "✅ Spreadsheet found: $SPREADSHEET_PATH"
    ls -lh "$SPREADSHEET_PATH"
else
    echo "❌ Spreadsheet NOT found: $SPREADSHEET_PATH"
fi

if [ -f "$LETTER_PATH" ]; then
    echo "✅ Letter found: $LETTER_PATH"
    ls -lh "$LETTER_PATH"
else
    echo "❌ Letter NOT found: $LETTER_PATH"
fi

echo ""
echo "=== Export Complete ==="