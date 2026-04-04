#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Parse Unfamiliar Config Result ==="

# Focus VSCode and save the file
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to focus VSCode window; continuing"
}

sleep 2

# Wait for file to be written
wait_for_file "/home/ga/workspace/api-gateway-config/gateway_config.yaml" 5

# Copy modified config to /tmp for verifier
WORKSPACE_FILE="/home/ga/workspace/api-gateway-config/gateway_config.yaml"
if [ -f "$WORKSPACE_FILE" ]; then
    cp "$WORKSPACE_FILE" /tmp/gateway_config_modified.yaml
    echo "✅ Config file copied to /tmp/gateway_config_modified.yaml"
else
    echo "⚠️ Warning: Config file not found at $WORKSPACE_FILE"
    touch /tmp/gateway_config_modified.yaml
fi

echo "✅ Export complete"
echo "Modified file: $WORKSPACE_FILE"