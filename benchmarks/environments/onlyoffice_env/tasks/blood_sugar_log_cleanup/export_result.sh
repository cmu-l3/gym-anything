#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Blood Sugar Log Cleanup Result ==="

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

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/blood_sugar_organized.xlsx"

if [ -f "$OUTPUT_PATH" ]; then
    echo "✅ Organized spreadsheet saved: $OUTPUT_PATH"
    ls -lh "$OUTPUT_PATH"
else
    echo "⚠️  Output file not found at: $OUTPUT_PATH"
    echo "Checking if file was saved with different name..."
    ls -lh /home/ga/Documents/Spreadsheets/ || true
fi

echo "=== Export Complete ==="