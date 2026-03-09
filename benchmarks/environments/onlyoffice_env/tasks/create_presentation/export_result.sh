#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Presentation Result ==="

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

PRES_PATH="/home/ga/Documents/Presentations/company_overview.pptx"

if [ -f "$PRES_PATH" ]; then
    echo "✅ Presentation saved: $PRES_PATH"
    ls -lh "$PRES_PATH"
else
    echo "⚠️ Presentation not found: $PRES_PATH"
fi

echo "=== Export Complete ==="
