#!/bin/bash
set -euo pipefail

echo "=== Exporting Email Results ==="

# Give Thunderbird time to save the sent email
sleep 2

# Export directory
EXPORT_DIR="/home/ga/Documents/results"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Copy Sent mbox file for verification
TB_PROFILE="/home/ga/.thunderbird/default"
if [ -f "$TB_PROFILE/Mail/Local Folders/Sent" ]; then
    cp "$TB_PROFILE/Mail/Local Folders/Sent" "$EXPORT_DIR/Sent.mbox"
    echo "✅ Exported Sent folder"
else
    echo "⚠️ Sent folder not found"
fi

echo "=== Export Complete ==="
