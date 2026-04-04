#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Event Listener Leak Fix Result ==="

# Focus VSCode and save
focus_vscode_window
{
  safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
  echo "⚠️ Failed to trigger save; file may already be saved"
}

# Wait for file to be written
wait_for_file "/home/ga/workspace/memory-leak-project/src/websocket-handler.js" 5

echo "✅ Export complete"
echo "File location: /home/ga/workspace/memory-leak-project/src/websocket-handler.js"