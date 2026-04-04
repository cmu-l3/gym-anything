#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting IRS Mileage Audit Log Result ==="

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

SHEET_PATH="/home/ga/Documents/Spreadsheets/mileage_log_2024_q1.xlsx"
NOTES_PATH="/home/ga/Documents/Spreadsheets/mileage_notes.txt"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Mileage log saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Mileage log not found: $SHEET_PATH"
fi

if [ -f "$NOTES_PATH" ]; then
    echo "✅ Trip notes available: $NOTES_PATH"
else
    echo "⚠️ Trip notes not found: $NOTES_PATH"
fi

echo "=== Export Complete ==="