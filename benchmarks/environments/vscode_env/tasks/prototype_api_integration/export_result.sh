#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Prototype API Integration Result ==="

WORKSPACE_DIR="/home/ga/workspace/weather_integration"

# Focus VSCode and save
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to save via VSCode; continuing"
}

# Wait for file to be written
wait_for_file "$WORKSPACE_DIR/weather_api.http" 5

# Export the HTTP request file to /tmp
if [ -f "$WORKSPACE_DIR/weather_api.http" ]; then
    cp "$WORKSPACE_DIR/weather_api.http" /tmp/weather_api.http
    echo "✅ HTTP request file exported to /tmp"
else
    echo "⚠️ HTTP request file not found"
    echo "" > /tmp/weather_api.http
fi

# Export any response files saved by REST Client (optional)
if [ -d "$WORKSPACE_DIR/.vscode" ]; then
    cp -r "$WORKSPACE_DIR/.vscode" /tmp/vscode_settings 2>/dev/null || true
fi

# Export git log to show iteration
cd "$WORKSPACE_DIR"
sudo -u ga git add -A 2>/dev/null || true
sudo -u ga git diff --cached > /tmp/git_changes.txt 2>/dev/null || echo "No git changes" > /tmp/git_changes.txt

echo "✅ Export complete"
echo "Main file: $WORKSPACE_DIR/weather_api.http"
ls -lh /tmp/weather_api.http