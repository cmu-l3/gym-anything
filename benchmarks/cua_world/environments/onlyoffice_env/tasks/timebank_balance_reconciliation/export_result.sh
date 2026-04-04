#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Time Bank Balance Reconciliation Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window and saving..."
    focus_onlyoffice_window || true
    sleep 1
    save_document ga :1
    sleep 3

    # Close ONLYOFFICE gracefully
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is fully closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Close text editor if still open
pkill -u ga gedit 2>/dev/null || true
pkill -u ga xed 2>/dev/null || true
pkill -u ga mousepad 2>/dev/null || true

# Wait a moment for file to be fully written to disk
sleep 1

# Check if the file was saved with the correct name
EXPECTED_PATH="/home/ga/Documents/Spreadsheets/sarah_chen_timebank.xlsx"
TEMPLATE_PATH="/home/ga/Documents/Spreadsheets/timebank_template.xlsx"

if [ -f "$EXPECTED_PATH" ]; then
    echo "✅ Time bank file saved correctly: $EXPECTED_PATH"
    ls -lh "$EXPECTED_PATH"
elif [ -f "$TEMPLATE_PATH" ]; then
    # Agent might have saved over the template instead
    echo "⚠️ File saved as template name, attempting to use it for verification"
    echo "Found: $TEMPLATE_PATH"
    ls -lh "$TEMPLATE_PATH"
else
    echo "❌ Time bank file not found at expected location"
    echo "Checking for any xlsx files in Spreadsheets directory:"
    ls -lh /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || echo "No xlsx files found"
fi

echo "=== Export Complete ==="