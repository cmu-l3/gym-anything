#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Prior Learning Portfolio Result ==="

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

PORTFOLIO_PATH="/home/ga/Documents/TextDocuments/PLA_Portfolio_Final.docx"

if [ -f "$PORTFOLIO_PATH" ]; then
    echo "✅ Portfolio saved: $PORTFOLIO_PATH"
    ls -lh "$PORTFOLIO_PATH"
else
    echo "⚠️  Portfolio not found at expected location: $PORTFOLIO_PATH"
    echo "Checking for alternative saves..."
    find /home/ga/Documents -name "*.docx" -type f -exec ls -lh {} \;
fi

echo "=== Export Complete ==="