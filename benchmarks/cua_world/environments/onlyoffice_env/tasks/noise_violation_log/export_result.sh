#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Noise Violation Log Result ==="

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

SHEET_PATH="/home/ga/Documents/Noise_Violation_Log.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Noise violation log saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Noise violation log not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="