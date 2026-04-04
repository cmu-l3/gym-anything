#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Roommate Expense Reconciliation Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE gracefully
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is fully closed
if is_onlyoffice_running; then
    echo "ONLYOFFICE still running, force closing..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written to disk
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/march_bills_raw.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Quick verification that file is valid
    file "$SHEET_PATH" | grep -q "Microsoft Excel" && echo "   File format: Valid Excel format" || echo "   Warning: File format check failed"
else
    echo "⚠️ Spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="