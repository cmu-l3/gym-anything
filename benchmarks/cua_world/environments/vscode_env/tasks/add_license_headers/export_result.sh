#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Add License Headers Result ==="

WORKSPACE_DIR="/home/ga/workspace/data-transformer"

# Focus VSCode and save all files
echo "Saving all files..."
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+k s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to send save commands; continuing anyway"
}

# Wait for files to be written
sleep 2

# Export all source files to /tmp for verification
echo "Exporting source files..."
sudo -u ga mkdir -p /tmp/license_export/{src/{utils,parsers,transformers},tests}

# Copy all relevant files
for file in \
    "src/main.py" \
    "src/utils/logger.py" \
    "src/utils/config.py" \
    "src/parsers/json_parser.py" \
    "src/transformers/mapper.js" \
    "src/transformers/validator.js" \
    "src/types.ts" \
    "tests/test_parser.py"; do
    
    if [ -f "$WORKSPACE_DIR/$file" ]; then
        sudo -u ga cp "$WORKSPACE_DIR/$file" "/tmp/license_export/$file" 2>/dev/null || true
        echo "  Exported: $file"
    fi
done

# Create a manifest of what was exported
ls -laR /tmp/license_export/ > /tmp/license_export_manifest.txt 2>&1

echo "✅ Export complete"
echo "Files exported to: /tmp/license_export/"
echo "Manifest: /tmp/license_export_manifest.txt"