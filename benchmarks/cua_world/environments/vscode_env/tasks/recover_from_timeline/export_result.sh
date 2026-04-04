#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Recover from Timeline Result ==="

WORKSPACE_DIR="/home/ga/workspace"
FILE_PATH="${WORKSPACE_DIR}/data_processor.py"
OUTPUT_DIR="/tmp/task_output"

# Try to save the file in VSCode before export
echo "Attempting to save file in VSCode..."
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; continuing with export"
}

# Wait for file to be saved
sleep 2

# Create output directory
sudo -u ga mkdir -p "${OUTPUT_DIR}"

# Export the recovered file to /tmp for verification
if [ -f "${FILE_PATH}" ]; then
    sudo -u ga cp "${FILE_PATH}" "${OUTPUT_DIR}/data_processor_recovered.py"
    echo "✅ Exported recovered file to ${OUTPUT_DIR}/data_processor_recovered.py"
    
    # Also copy directly to /tmp for easier verifier access
    sudo -u ga cp "${FILE_PATH}" "/tmp/data_processor.py"
    echo "✅ Copied file to /tmp/data_processor.py for verification"
    
    # Show first few lines for debugging
    echo ""
    echo "File preview (first 30 lines):"
    head -n 30 "${FILE_PATH}" || true
else
    echo "⚠️ Warning: data_processor.py not found at ${FILE_PATH}"
    echo "File not found" > "/tmp/data_processor.py"
fi

# Export file metadata for debugging
if [ -f "${FILE_PATH}" ]; then
    echo ""
    echo "File info:"
    ls -lh "${FILE_PATH}"
    echo ""
    echo "File size: $(wc -l < "${FILE_PATH}") lines"
    echo "Contains validate_headers: $(grep -c 'def validate_headers' "${FILE_PATH}" || echo '0')"
fi

echo "✅ Export complete"