#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Medication Reconciliation Result ==="

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

EXPECTED_FILE="/home/ga/Documents/Spreadsheets/dad_medications_reconciled.xlsx"
ORIGINAL_FILE="/home/ga/Documents/Spreadsheets/dad_medications_messy.xlsx"

if [ -f "$EXPECTED_FILE" ]; then
    echo "✅ Reconciled medication file saved: $EXPECTED_FILE"
    ls -lh "$EXPECTED_FILE"
elif [ -f "$ORIGINAL_FILE" ]; then
    echo "⚠️  File still has original name. Looking for any medication files..."
    find /home/ga/Documents/Spreadsheets -name "*med*" -type f -ls
else
    echo "⚠️  No medication spreadsheet found at expected locations"
fi

echo "=== Export Complete ==="