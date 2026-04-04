#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting REST API Testing Result ==="

# Focus VSCode and save all files
focus_vscode_window
{
safe_xdotool ga :1 key --delay 200 ctrl+shift+s
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to send save commands; continuing"
}

sleep 2

# Wait for the HTTP file to be created
HTTP_FILE="/home/ga/workspace/api_test/api-tests.http"
if [ -f "$HTTP_FILE" ]; then
    echo "✅ api-tests.http found"
    # Copy to /tmp for easy verification
    cp "$HTTP_FILE" /tmp/api-tests.http 2>/dev/null || true
else
    echo "⚠️ api-tests.http not found at $HTTP_FILE"
    touch /tmp/api-tests.http
fi

# Stop mock API server
echo "Stopping mock API server..."
pkill -f "mock-api-server.js" || true

echo "✅ Export complete"
echo "HTTP file location: $HTTP_FILE"