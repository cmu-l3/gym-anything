#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Therapist Comparison Result ==="

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

# Close gedit if it's still open
pkill -u ga gedit || true

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/therapist_comparison.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="