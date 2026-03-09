#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Read-a-thon Tracker Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
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

# Wait a moment for files to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/ReadAthon_Data.xlsx"
DOC_PATH="/home/ga/Documents/TextDocuments/Collection_Letters.docx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Spreadsheet not found: $SHEET_PATH"
fi

if [ -f "$DOC_PATH" ]; then
    echo "✅ Collection letters document saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
else
    echo "ℹ️ Collection letters document not found (optional): $DOC_PATH"
fi

echo "=== Export Complete ==="