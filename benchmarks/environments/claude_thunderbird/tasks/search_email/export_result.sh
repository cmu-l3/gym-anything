#!/bin/bash
set -euo pipefail

echo "=== Exporting Email Status ==="

# Give Thunderbird time to save
sleep 2

# Export directory
EXPORT_DIR="/home/ga/Documents/results"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Copy Inbox to check for flagged status
TB_PROFILE="/home/ga/.thunderbird/default"
if [ -f "$TB_PROFILE/Mail/Local Folders/Inbox" ]; then
    cp "$TB_PROFILE/Mail/Local Folders/Inbox" "$EXPORT_DIR/Inbox.mbox"
    echo "✅ Exported Inbox"
fi

# Also copy the MSF (Mail Summary File) which contains flags
if [ -f "$TB_PROFILE/Mail/Local Folders/Inbox.msf" ]; then
    cp "$TB_PROFILE/Mail/Local Folders/Inbox.msf" "$EXPORT_DIR/Inbox.msf"
    echo "✅ Exported Inbox summary"
fi

echo "=== Export Complete ==="
