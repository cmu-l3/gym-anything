#!/bin/bash
set -euo pipefail

echo "=== Exporting Address Book ==="

# Give Thunderbird time to save
sleep 2

# Export directory
EXPORT_DIR="/home/ga/Documents/results"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Copy address book database
TB_PROFILE="/home/ga/.thunderbird/default"
if [ -f "$TB_PROFILE/abook.sqlite" ]; then
    cp "$TB_PROFILE/abook.sqlite" "$EXPORT_DIR/abook.sqlite"
    echo "✅ Exported address book"
else
    echo "⚠️ Address book not found"
fi

# Also copy any other address book files
if [ -f "$TB_PROFILE/history.sqlite" ]; then
    cp "$TB_PROFILE/history.sqlite" "$EXPORT_DIR/history.sqlite" || true
fi

echo "=== Export Complete ==="
