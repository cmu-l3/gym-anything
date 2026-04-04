#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Backyard Beekeeping Log Result ==="

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

# Wait a moment for files to be fully written
sleep 1

OUTPUT_PATH="/home/ga/Documents/Spreadsheets/beekeeping_log_2025.xlsx"
INPUT_PATH="/home/ga/Documents/Spreadsheets/bee_inspection_notes.xlsx"

echo "Checking for output file..."
if [ -f "$OUTPUT_PATH" ]; then
    echo "✅ Output file created: $OUTPUT_PATH"
    ls -lh "$OUTPUT_PATH"
else
    echo "⚠️ Output file not found at: $OUTPUT_PATH"
    echo "Checking if input file was modified instead..."
    if [ -f "$INPUT_PATH" ]; then
        ls -lh "$INPUT_PATH"
    fi
fi

echo "=== Export Complete ==="