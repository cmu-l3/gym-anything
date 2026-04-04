#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sleep Pattern Analyzer Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Attempting to save document..."
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
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Close any text editors that might be open
pkill -f "xdg-open.*sleep_notes" || true
pkill -f "gedit" || true
pkill -f "mousepad" || true

# Wait for files to be fully written
sleep 2

EXPECTED_PATH="/home/ga/Documents/Spreadsheets/sleep_analysis.xlsx"

if [ -f "$EXPECTED_PATH" ]; then
    echo "✅ Sleep analysis spreadsheet found: $EXPECTED_PATH"
    ls -lh "$EXPECTED_PATH"
else
    echo "⚠️ Expected spreadsheet not found: $EXPECTED_PATH"
    echo "Checking for other xlsx files in directory..."
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || echo "No xlsx files found"
fi

echo "=== Export Complete ==="