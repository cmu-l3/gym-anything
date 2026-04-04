#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Polish Demo Script Result ==="

# Focus VSCode and save file
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save command; file may already be saved"
}

# Wait for file to be written
wait_for_file "/home/ga/workspace/demo_prep/data_processor.py" 5

# Copy the script to /tmp for verification
cp /home/ga/workspace/demo_prep/data_processor.py /tmp/data_processor.py 2>/dev/null || true
cp /home/ga/workspace/demo_prep/sample_orders.csv /tmp/sample_orders.csv 2>/dev/null || true

echo "✅ Export complete"
echo "Script location: /home/ga/workspace/demo_prep/data_processor.py"