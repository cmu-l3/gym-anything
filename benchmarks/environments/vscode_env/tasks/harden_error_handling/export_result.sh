#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Error Handling Result ==="

# Focus VSCode and save file
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; file may already be saved"
}

# Wait for file to be written
wait_for_file "/home/ga/workspace/data_pipeline/fetch_data.py" 5

# Copy file to /tmp for verification
sudo -u ga cp /home/ga/workspace/data_pipeline/fetch_data.py /tmp/fetch_data_result.py 2>/dev/null || true

echo "✅ Export complete"
echo "Modified script: /home/ga/workspace/data_pipeline/fetch_data.py"