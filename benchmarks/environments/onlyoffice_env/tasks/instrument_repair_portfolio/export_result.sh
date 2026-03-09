#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Instrument Repair Portfolio Result ==="

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

OUTPUT_FILE="/home/ga/Documents/Spreadsheets/instrument_portfolio.xlsx"

if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Spreadsheet saved: $OUTPUT_FILE"
    ls -lh "$OUTPUT_FILE"
else
    echo "⚠️ Spreadsheet not found: $OUTPUT_FILE"
fi

echo "=== Export Complete ==="