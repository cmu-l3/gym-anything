#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sensory Incident Tracker Result ==="

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

ANALYSIS_PATH="/home/ga/Documents/Spreadsheets/sensory_analysis_for_OT.xlsx"
RAW_PATH="/home/ga/Documents/Spreadsheets/sensory_raw_notes.xlsx"

echo "Checking for expected files..."

if [ -f "$RAW_PATH" ]; then
    echo "✅ Raw data file exists: $RAW_PATH"
    ls -lh "$RAW_PATH"
else
    echo "⚠️ Raw data file not found: $RAW_PATH"
fi

if [ -f "$ANALYSIS_PATH" ]; then
    echo "✅ Analysis file created: $ANALYSIS_PATH"
    ls -lh "$ANALYSIS_PATH"
else
    echo "⚠️ Analysis file not found: $ANALYSIS_PATH"
    echo "   Agent may not have created the required output file."
fi

echo "=== Export Complete ==="