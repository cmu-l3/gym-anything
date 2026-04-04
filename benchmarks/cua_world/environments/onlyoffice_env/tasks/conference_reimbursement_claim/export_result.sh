#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Conference Reimbursement Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    
    # Save current document (might be raw receipts or final claim)
    save_document ga :1
    sleep 2
    
    # Try to save again to be sure
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
sleep 2

RAW_PATH="/home/ga/Documents/Spreadsheets/conference_receipts_raw.xlsx"
FINAL_PATH="/home/ga/Documents/Spreadsheets/reimbursement_claim_final.xlsx"

echo ""
echo "Checking for output files..."

if [ -f "$RAW_PATH" ]; then
    echo "✅ Raw receipts file exists: $RAW_PATH"
    ls -lh "$RAW_PATH"
else
    echo "⚠️ Raw receipts file not found: $RAW_PATH"
fi

if [ -f "$FINAL_PATH" ]; then
    echo "✅ Final reimbursement claim created: $FINAL_PATH"
    ls -lh "$FINAL_PATH"
else
    echo "⚠️ Final reimbursement claim not found: $FINAL_PATH"
    echo "   Agent may have modified raw file instead of creating new one"
fi

echo ""
echo "=== Export Complete ==="