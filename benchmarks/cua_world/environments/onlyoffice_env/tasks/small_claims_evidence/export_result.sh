#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Small Claims Evidence Result ==="

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

# Close any text editors that might be open
pkill -u ga gedit 2>/dev/null || true
pkill -u ga xed 2>/dev/null || true

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/deposit_evidence.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Evidence spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Evidence spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="