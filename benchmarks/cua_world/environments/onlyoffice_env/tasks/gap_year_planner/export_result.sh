#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Gap Year Planner Result ==="

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

PLAN_PATH="/home/ga/Documents/Spreadsheets/gap_year_plan.xlsx"

if [ -f "$PLAN_PATH" ]; then
    echo "✅ Gap year plan saved: $PLAN_PATH"
    ls -lh "$PLAN_PATH"
else
    echo "⚠️ Gap year plan not found at: $PLAN_PATH"
    echo "Checking for original file..."
    RAW_PATH="/home/ga/Documents/Spreadsheets/gap_year_raw_data.xlsx"
    if [ -f "$RAW_PATH" ]; then
        echo "ℹ️ Original raw data file exists: $RAW_PATH"
        ls -lh "$RAW_PATH"
    fi
fi

echo "=== Export Complete ==="