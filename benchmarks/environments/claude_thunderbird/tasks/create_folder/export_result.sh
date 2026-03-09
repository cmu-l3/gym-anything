#!/bin/bash
set -euo pipefail

echo "=== Exporting Folder Structure ==="

# Give Thunderbird time to create folder
sleep 2

# Export directory
EXPORT_DIR="/home/ga/Documents/results"
sudo -u ga mkdir -p "$EXPORT_DIR"

# List all folders in Local Folders
TB_PROFILE="/home/ga/.thunderbird/default"
MAIL_DIR="$TB_PROFILE/Mail/Local Folders"

if [ -d "$MAIL_DIR" ]; then
    # Create folder list
    ls -1 "$MAIL_DIR" > "$EXPORT_DIR/folder_list.txt" 2>/dev/null || true
    echo "✅ Exported folder list"

    # Show folder count
    FOLDER_COUNT=$(ls "$MAIL_DIR" 2>/dev/null | grep -v '\.msf$' | wc -l)
    echo "Found $FOLDER_COUNT folders"
fi

echo "=== Export Complete ==="
