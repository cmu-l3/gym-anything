#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Artifact Catalog Result ==="

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

SHEET_PATH="/home/ga/Documents/Spreadsheets/archaeology_survey/artifact_catalog.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Artifact catalog saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Artifact catalog not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="