#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Photographer Shoot Coordinator Result ==="

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

# Wait a moment for files to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Photography/shoot_master_schedule.xlsx"
DOC_PATH="/home/ga/Documents/Photography/chen_family_shoot_plan.docx"

echo "Checking for required files..."

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Spreadsheet not found: $SHEET_PATH"
fi

if [ -f "$DOC_PATH" ]; then
    echo "✅ Client document saved: $DOC_PATH"
    ls -lh "$DOC_PATH"
else
    echo "⚠️ Client document not found: $DOC_PATH (agent may not have created it yet)"
fi

echo "=== Export Complete ==="