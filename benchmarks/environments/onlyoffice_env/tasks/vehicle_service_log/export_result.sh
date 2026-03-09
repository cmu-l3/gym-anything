#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Vehicle Service Log Result ==="

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

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/vehicle_maintenance.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Vehicle maintenance spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Spreadsheet not found at expected location: $SHEET_PATH"
    # Search for any vehicle_maintenance files
    echo "Searching for vehicle_maintenance.xlsx in Documents..."
    find /home/ga/Documents -name "*vehicle*maintenance*.xlsx" -type f 2>/dev/null || echo "No matching files found"
fi

echo "=== Export Complete ==="