#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Estate Asset Inventory Result ==="

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

RAW_FILE="/home/ga/Documents/Spreadsheets/estate_inventory_raw.xlsx"

if [ -f "$RAW_FILE" ]; then
    echo "✅ Estate inventory saved: $RAW_FILE"
    ls -lh "$RAW_FILE"
else
    echo "⚠️ Estate inventory not found: $RAW_FILE"
fi

echo "=== Export Complete ==="