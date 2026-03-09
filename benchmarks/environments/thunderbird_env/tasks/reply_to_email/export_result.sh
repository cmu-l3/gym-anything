#!/bin/bash
set -euo pipefail

echo "=== Exporting Reply Results ==="

# Give Thunderbird time to save
sleep 2

# Export directory
EXPORT_DIR="/home/ga/Documents/results"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Copy Sent folder
TB_PROFILE="/home/ga/.thunderbird/default"
if [ -f "$TB_PROFILE/Mail/Local Folders/Sent" ]; then
    cp "$TB_PROFILE/Mail/Local Folders/Sent" "$EXPORT_DIR/Sent.mbox"
    echo "✅ Exported Sent folder"
fi

echo "=== Export Complete ==="
