#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Theater Prop Tracker Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window and saving..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Save the document
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

# Wait for file to be fully written
sleep 2

# Check for both possible output locations
OUTPUT_PATH="/home/ga/Documents/Spreadsheets/props_organized.xlsx"
ORIGINAL_PATH="/home/ga/Documents/Spreadsheets/props_messy.xlsx"

if [ -f "$OUTPUT_PATH" ]; then
    echo "✅ Organized spreadsheet saved: $OUTPUT_PATH"
    ls -lh "$OUTPUT_PATH"
elif [ -f "$ORIGINAL_PATH" ]; then
    echo "⚠️ File exists but may not have been saved as props_organized.xlsx"
    echo "   Found: $ORIGINAL_PATH"
    ls -lh "$ORIGINAL_PATH"
else
    echo "⚠️ No output files found"
fi

echo "=== Export Complete ==="