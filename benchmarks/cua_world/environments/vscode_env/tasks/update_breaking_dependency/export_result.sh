#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Update Breaking Dependency Result ==="

WORKSPACE_DIR="/home/ga/workspace/api-project"

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Save all open files
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save files via xdotool; files may already be saved"
}

# Wait for files to be written
sleep 2

# Wait for key files
wait_for_file "$WORKSPACE_DIR/package.json" 5
wait_for_file "$WORKSPACE_DIR/lib/payment-client.js" 5
wait_for_file "$WORKSPACE_DIR/middleware/api-client.js" 5

# Export package.json version info
if [ -f "$WORKSPACE_DIR/node_modules/axios/package.json" ]; then
    echo "Axios package info:"
    cat "$WORKSPACE_DIR/node_modules/axios/package.json" | grep -A 2 '"version"' || echo "Could not read axios version"
else
    echo "⚠️ node_modules/axios not found"
fi

echo "✅ Export complete"
echo "Files at: $WORKSPACE_DIR"