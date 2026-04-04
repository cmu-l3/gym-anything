#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Transfer Credit Tracker Result ==="

# Close gedit if it's still open
su - ga -c "DISPLAY=:1 pkill gedit" 2>/dev/null || true
sleep 1

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE and saving document..."
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE gracefully
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
fi

# Wait for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/transfer_analysis.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="