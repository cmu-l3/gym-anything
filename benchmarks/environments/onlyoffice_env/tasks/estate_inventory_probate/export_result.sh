#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Estate Inventory Result ==="

# Close gedit if it's open
pkill -u ga gedit || true
sleep 1

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

SHEET_PATH="/home/ga/Documents/Estate_Inventory.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Estate inventory saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Quick check if file has content
    SIZE=$(stat -f%z "$SHEET_PATH" 2>/dev/null || stat -c%s "$SHEET_PATH" 2>/dev/null || echo "0")
    if [ "$SIZE" -gt 5000 ]; then
        echo "✅ File appears to have content (${SIZE} bytes)"
    else
        echo "⚠️  File seems small (${SIZE} bytes) - may not be complete"
    fi
else
    echo "❌ Estate inventory not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="