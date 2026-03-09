#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Macro Nutrition Tracker Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2

    # Save again to be extra sure (sometimes first save doesn't register)
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
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/macro_log.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Macro tracking spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Macro tracking spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="