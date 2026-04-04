#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Custom Cake Order Timeline Result ==="

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

# Check both possible filenames
SHEET_PATH_RENAMED="/home/ga/Documents/Spreadsheets/CakeOrders_ProductionTimeline.xlsx"
SHEET_PATH_ORIGINAL="/home/ga/Documents/Spreadsheets/CakeOrders_RawInfo.xlsx"

if [ -f "$SHEET_PATH_RENAMED" ]; then
    echo "✅ Production timeline saved as: $SHEET_PATH_RENAMED"
    ls -lh "$SHEET_PATH_RENAMED"
elif [ -f "$SHEET_PATH_ORIGINAL" ]; then
    echo "✅ Spreadsheet saved (original name): $SHEET_PATH_ORIGINAL"
    ls -lh "$SHEET_PATH_ORIGINAL"
    echo "ℹ️  Note: File not renamed to CakeOrders_ProductionTimeline.xlsx (will check for timeline sheet)"
else
    echo "⚠️ No spreadsheet found at expected locations"
fi

echo "=== Export Complete ==="