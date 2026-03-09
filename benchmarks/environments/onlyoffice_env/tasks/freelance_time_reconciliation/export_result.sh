#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Freelance Time Reconciliation Result ==="

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

# Close any text editors that might have time_logs.txt open
su - ga -c "DISPLAY=:1 pkill -f 'xdg-open.*time_logs.txt'" || true
su - ga -c "DISPLAY=:1 pkill -f gedit" || true
su - ga -c "DISPLAY=:1 pkill -f mousepad" || true

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/freelance_timesheet_dec.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Timesheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Timesheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="