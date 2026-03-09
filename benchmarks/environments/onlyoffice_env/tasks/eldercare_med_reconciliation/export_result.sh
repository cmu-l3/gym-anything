#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Eldercare Med Reconciliation Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window and saving..."
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 3

    # Close ONLYOFFICE
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force killing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Close gedit if still open
pkill -u ga gedit || true

# Wait a moment for file to be fully written
sleep 1

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/november_med_reconciliation.xlsx"

if [ -f "$OUTPUT_PATH" ]; then
    echo "✅ Spreadsheet saved: $OUTPUT_PATH"
    ls -lh "$OUTPUT_PATH"
else
    echo "⚠️ Spreadsheet not found: $OUTPUT_PATH"
fi

echo "=== Export Complete ==="