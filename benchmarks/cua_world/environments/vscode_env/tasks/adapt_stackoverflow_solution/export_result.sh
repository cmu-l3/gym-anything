#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Adapt Stack Overflow Solution Result ==="

WORKSPACE_DIR="/home/ga/workspace/api_project"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to save files; continuing"
}

# Wait for files to be written
sleep 2

# Copy relevant files to /tmp for verification
echo "Copying files for verification..."

# Copy rate limiter implementation
if [ -f "$WORKSPACE_DIR/src/middleware/rate_limiter.js" ]; then
    cp "$WORKSPACE_DIR/src/middleware/rate_limiter.js" /tmp/rate_limiter.js
    echo "✅ Copied rate_limiter.js"
else
    echo "" > /tmp/rate_limiter.js
    echo "⚠️ rate_limiter.js not found"
fi

# Copy server file
if [ -f "$WORKSPACE_DIR/src/server.js" ]; then
    cp "$WORKSPACE_DIR/src/server.js" /tmp/server.js
    echo "✅ Copied server.js"
else
    echo "" > /tmp/server.js
    echo "⚠️ server.js not found"
fi

# Check if example file was cleaned up
if [ ! -f "$WORKSPACE_DIR/src/utils/rate_limiter_example.js" ]; then
    echo "DELETED" > /tmp/example_cleanup_status.txt
    echo "✅ Example file was deleted"
elif [ -f "$WORKSPACE_DIR/docs/references/rate_limiter_example.js" ]; then
    echo "MOVED" > /tmp/example_cleanup_status.txt
    echo "✅ Example file was moved to docs/references"
else
    echo "STILL_PRESENT" > /tmp/example_cleanup_status.txt
    echo "⚠️ Example file still in original location"
fi

# Create a summary of what files exist
ls -la "$WORKSPACE_DIR/src/middleware/" > /tmp/middleware_listing.txt 2>&1 || echo "No middleware dir" > /tmp/middleware_listing.txt
ls -la "$WORKSPACE_DIR/src/utils/" > /tmp/utils_listing.txt 2>&1 || echo "No utils dir" > /tmp/utils_listing.txt

echo "✅ Export complete"
echo "Files exported to /tmp for verification"